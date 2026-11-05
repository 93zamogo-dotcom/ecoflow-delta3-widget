import Foundation

public struct StationStatus: Codable, Equatable, Sendable {
    public var sn: String
    public var online: Bool
    public var soc: Int?
    public var inputW: Int?
    public var outputW: Int?
    public var solarW: Int?
    public var acOutW: Int?
    public var acInW: Int?
    public var state: String?
    public var remainMin: Int?
    public var tempC: Double?
    public var cycles: Int?
    public var updatedAt: Date

    public init(
        sn: String,
        online: Bool,
        soc: Int? = nil,
        inputW: Int? = nil,
        outputW: Int? = nil,
        solarW: Int? = nil,
        acOutW: Int? = nil,
        acInW: Int? = nil,
        state: String? = nil,
        remainMin: Int? = nil,
        tempC: Double? = nil,
        cycles: Int? = nil,
        updatedAt: Date = Date()
    ) {
        self.sn = sn
        self.online = online
        self.soc = soc
        self.inputW = inputW
        self.outputW = outputW
        self.solarW = solarW
        self.acOutW = acOutW
        self.acInW = acInW
        self.state = state
        self.remainMin = remainMin
        self.tempC = tempC
        self.cycles = cycles
        self.updatedAt = updatedAt
    }

    public var stateLabelRU: String {
        switch state {
        case "charging": return "Заряд"
        case "discharging": return "Разряд"
        case "idle": return "Простой"
        default: return "—"
        }
    }

    public var remainLabel: String {
        guard let remainMin else { return "—" }
        let h = remainMin / 60
        let m = remainMin % 60
        if h == 0 { return "\(m)м" }
        return "\(h)ч \(String(format: "%02d", m))м"
    }
}

public enum AppGroup {
    public static let id = "group.com.oleksandr.ecoflowdelta"
    public static let statusKey = "stationStatus"
    public static let credentialsKey = "credentials"
}

public struct EcoFlowCredentials: Codable, Equatable, Sendable {
    public var email: String
    public var password: String
    public var sn: String
    public var region: String

    public init(email: String, password: String, sn: String, region: String = "global") {
        self.email = email
        self.password = password
        self.sn = sn
        self.region = region
    }
}

public final class StatusStore {
    private let defaults: UserDefaults?

    public init(suiteName: String = AppGroup.id) {
        defaults = UserDefaults(suiteName: suiteName)
    }

    public func save(_ status: StationStatus) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults?.set(data, forKey: AppGroup.statusKey)
    }

    public func load() -> StationStatus? {
        guard let data = defaults?.data(forKey: AppGroup.statusKey) else { return nil }
        return try? JSONDecoder().decode(StationStatus.self, from: data)
    }

    public func saveCredentials(_ credentials: EcoFlowCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        defaults?.set(data, forKey: AppGroup.credentialsKey)
    }

    public func loadCredentials() -> EcoFlowCredentials? {
        guard let data = defaults?.data(forKey: AppGroup.credentialsKey) else { return nil }
        return try? JSONDecoder().decode(EcoFlowCredentials.self, from: data)
    }
}
