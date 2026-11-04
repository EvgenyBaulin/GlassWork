import GlassWorkCore
import GlassWorkUI
import SwiftUI
import WidgetKit

/// Moves through the photos on its own, so a new photo costs no reload from the app.
struct PhotoProvider: TimelineProvider {
    private static let entries = 8

    let kind: WidgetKind
    private let store = SnapshotStore()

    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(date: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(at: .now, base: snapshot(), size: size(context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let base = snapshot()
        let size = size(context)
        let start = Date.now
        let entries = (0 ..< Self.entries).map {
            entry(at: start.addingTimeInterval(Double($0) * PhotoRotation.interval), base: base, size: size)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func snapshot() -> WidgetSnapshot? {
        store.read(WidgetSnapshot.self, for: WidgetSnapshot.key)
    }

    private func size(_ context: Context) -> WidgetSize {
        switch context.family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    /// Each entry carries only the images it draws.
    private func entry(at date: Date, base: WidgetSnapshot?, size: WidgetSize) -> SnapshotEntry {
        guard var snapshot = base else { return SnapshotEntry(date: date, snapshot: nil) }
        let photos = kind == .photoFrame
            ? snapshot.personal?.photoFrame.photos ?? []
            : snapshot.personal?.onThisDay.photos ?? []
        let keys = photos.imageKeys(at: PhotoRotation.index(at: date, count: photos.count), size: size)
        snapshot.photoImages = Dictionary(uniqueKeysWithValues: keys.compactMap { key in
            store.readData(for: key).map { (key, $0) }
        })
        return SnapshotEntry(date: date, snapshot: snapshot)
    }
}

@MainActor
private func photoConfiguration(_ kind: WidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: PhotoProvider(kind: kind)) { entry in
        KindView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.title)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
}

struct PhotoFrameKindWidget: Widget {
    var body: some WidgetConfiguration {
        photoConfiguration(.photoFrame)
    }
}

struct OnThisDayKindWidget: Widget {
    var body: some WidgetConfiguration {
        photoConfiguration(.onThisDay)
    }
}
