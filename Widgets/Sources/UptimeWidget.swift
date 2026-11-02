import GlassWorkCore
import SwiftUI
import WidgetKit

struct UptimeEntry: TimelineEntry {
    let date: Date
    let heartbeat: Heartbeat?
}

struct UptimeProvider: TimelineProvider {
    private let store = SnapshotStore()

    func placeholder(in _: Context) -> UptimeEntry {
        UptimeEntry(date: .now, heartbeat: Heartbeat(updatedAt: .now, bootTime: .now.addingTimeInterval(-273_600)))
    }

    func getSnapshot(in context: Context, completion: @escaping (UptimeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<UptimeEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> UptimeEntry {
        UptimeEntry(date: .now, heartbeat: store.read(Heartbeat.self, for: Heartbeat.key))
    }
}

struct UptimeWidgetView: View {
    let entry: UptimeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Uptime", systemImage: "clock.arrow.circlepath")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let beat = entry.heartbeat {
                Text(CompactDuration.format(entry.date.timeIntervalSince(beat.bootTime)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("Since \(beat.bootTime.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Open GlassWork")
                    .font(.headline)
                Text("No shared data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct UptimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "io.github.evgenybaulin.glasswork.uptime", provider: UptimeProvider()) { entry in
            UptimeWidgetView(entry: entry)
        }
        .configurationDisplayName("Uptime")
        .description("How long since your Mac started up.")
        .supportedFamilies([.systemSmall])
    }
}
