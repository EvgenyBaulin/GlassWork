import GlassWorkCore
import GlassWorkUI
import SwiftUI
import WidgetKit

@main
struct GlassWorkWidgets: WidgetBundle {
    var body: some Widget {
        ActivityKindWidget()
        BatteryKindWidget()
        MacHealthKindWidget()
        UptimeKindWidget()
        DigitalClockKindWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    private let store = SnapshotStore()

    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(date: .now))
    }

    func getSnapshot(in _: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// One entry a minute, so clocks and ages stay right between the app's refreshes.
    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let start = Date.now
        let entries = (0 ..< 15).map { entry(at: start.addingTimeInterval(Double($0) * 60)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> SnapshotEntry {
        SnapshotEntry(date: date, snapshot: store.read(WidgetSnapshot.self, for: WidgetSnapshot.key))
    }
}

struct KindView: View {
    let kind: WidgetKind
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                WidgetFace(kind: kind, size: size, snapshot: snapshot, now: entry.date)
            } else {
                Text(loc("Open GlassWork to start")).foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

@MainActor
private func configuration(_ kind: WidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: SnapshotProvider()) { entry in
        KindView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.title)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
}

struct ActivityKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.activity)
    }
}

struct BatteryKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.battery)
    }
}

struct MacHealthKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.macHealth)
    }
}

struct UptimeKindWidget: Widget {
    var body: some WidgetConfiguration { configuration(.uptime) }
}

struct DigitalClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.digitalClock)
    }
}
