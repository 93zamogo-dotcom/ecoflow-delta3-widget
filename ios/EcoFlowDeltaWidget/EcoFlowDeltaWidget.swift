import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    let store = StatusStore()

    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), status: StationStatus(sn: "DELTA3", online: true, soc: 78, inputW: 320, outputW: 110, state: "charging"))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), status: store.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let status = store.load()
        let entry = StatusEntry(date: Date(), status: status)
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: StationStatus?
}

struct EcoFlowDeltaWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DELTA 3 1500")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.mint)

            if let status = entry.status {
                HStack(alignment: .firstTextBaseline) {
                    Text(status.soc.map { "\($0)%" } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(socColor(status.soc))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(status.stateLabelRU)
                            .font(.subheadline.weight(.semibold))
                        Text(status.online ? "online" : "offline")
                            .font(.caption2)
                            .foregroundStyle(status.online ? .green : .red)
                    }
                }

                HStack {
                    metric("Вход", status.inputW)
                    Spacer()
                    metric("Выход", status.outputW)
                    Spacer()
                    metric("PV", status.solarW)
                }
                .font(.caption)

                Text("осталось \(status.remainLabel)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Нет данных")
                    .foregroundStyle(.secondary)
                Text("Откройте приложение и обновите статус")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.04, green: 0.11, blue: 0.09)
        }
    }

    private func metric(_ title: String, _ value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.secondary)
            Text(value.map { "\($0) W" } ?? "—")
                .foregroundStyle(.white)
        }
    }

    private func socColor(_ soc: Int?) -> Color {
        guard let soc else { return .gray }
        if soc <= 20 { return .red }
        if soc <= 40 { return .orange }
        return .green
    }
}

@main
struct EcoFlowDeltaWidget: Widget {
    let kind = "EcoFlowDeltaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            EcoFlowDeltaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("EcoFlow DELTA 3")
        .description("Заряд, вход/выход и состояние станции.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
