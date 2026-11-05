import SwiftUI

@main
struct EcoFlowDeltaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @StateObject private var model = StationViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Аккаунт EcoFlow") {
                    TextField("Email", text: $model.email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Пароль", text: $model.password)
                    TextField("SN станции", text: $model.sn)
                        .textInputAutocapitalization(.characters)
                    Picker("Регион", selection: $model.region) {
                        ForEach(EcoFlowRegion.allCases) { region in
                            Text(region.title).tag(region.rawValue)
                        }
                    }
                    Button("Сохранить и обновить") {
                        Task { await model.saveAndRefresh() }
                    }
                    .disabled(model.isLoading)
                }

                Section("DELTA 3 1500") {
                    if let status = model.status {
                        LabeledContent("Заряд", value: status.soc.map { "\($0)%" } ?? "—")
                        LabeledContent("Состояние", value: status.stateLabelRU)
                        LabeledContent("Вход", value: watts(status.inputW))
                        LabeledContent("Выход", value: watts(status.outputW))
                        LabeledContent("Солнце", value: watts(status.solarW))
                        LabeledContent("Осталось", value: status.remainLabel)
                        LabeledContent("Online", value: status.online ? "да" : "нет")
                        LabeledContent("Обновлено", value: status.updatedAt.formatted(date: .omitted, time: .shortened))
                    } else {
                        Text("Нет данных. Заполните аккаунт и SN.")
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.errorText {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("EcoFlow")
            .overlay {
                if model.isLoading {
                    ProgressView("Связь со станцией…")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task { model.loadSaved() }
    }

    private func watts(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value) W"
    }
}

@MainActor
final class StationViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var sn = ""
    @Published var region = EcoFlowRegion.global.rawValue
    @Published var status: StationStatus?
    @Published var errorText: String?
    @Published var isLoading = false

    private let store = StatusStore()
    private let bridgeURLKey = "bridgeURL"

    /// Temporary path without embedding MQTT: poll a local/remote Python bridge.
    /// Replace with CocoaMQTT in-app once Xcode + MQTT package are available.
    @Published var bridgeURL = UserDefaults.standard.string(forKey: "bridgeURL") ?? "http://127.0.0.1:8787"

    func loadSaved() {
        if let creds = store.loadCredentials() {
            email = creds.email
            password = creds.password
            sn = creds.sn
            region = creds.region
        }
        status = store.load()
        bridgeURL = UserDefaults.standard.string(forKey: bridgeURLKey) ?? bridgeURL
    }

    func saveAndRefresh() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }

        let creds = EcoFlowCredentials(email: email, password: password, sn: sn, region: region)
        store.saveCredentials(creds)
        UserDefaults.standard.set(bridgeURL, forKey: bridgeURLKey)

        do {
            // Prefer bridge while native MQTT package is not wired.
            guard let url = URL(string: bridgeURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/status/refresh") else {
                throw URLError(.badURL)
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw EcoFlowClientError.badResponse(String(data: data, encoding: .utf8) ?? "bridge error")
            }
            let decoded = try JSONDecoder().decode(BridgeStatusDTO.self, from: data)
            let mapped = decoded.asStatus()
            status = mapped
            store.save(mapped)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct BridgeStatusDTO: Decodable {
    let sn: String
    let online: Bool
    let soc: Int?
    let input_w: Int?
    let output_w: Int?
    let solar_w: Int?
    let ac_out_w: Int?
    let ac_in_w: Int?
    let state: String?
    let remain_min: Int?
    let temp_c: Double?
    let cycles: Int?
    let updated_at: Double?

    func asStatus() -> StationStatus {
        StationStatus(
            sn: sn,
            online: online,
            soc: soc,
            inputW: input_w,
            outputW: output_w,
            solarW: solar_w,
            acOutW: ac_out_w,
            acInW: ac_in_w,
            state: state,
            remainMin: remain_min,
            tempC: temp_c,
            cycles: cycles,
            updatedAt: Date(timeIntervalSince1970: updated_at ?? Date().timeIntervalSince1970)
        )
    }
}
