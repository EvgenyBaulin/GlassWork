import AppIntents
import GlassWorkCore
import GlassWorkUI
import SwiftUI
import WidgetKit

enum NowPlayingAction: String, AppEnum {
    case toggle, next, previous

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Playback action"
    static let caseDisplayRepresentations: [NowPlayingAction: DisplayRepresentation] = [
        .toggle: "Play or Pause",
        .next: "Next Track",
        .previous: "Previous Track",
    ]

    var command: NowPlayingCommand {
        switch self {
        case .toggle: .toggle
        case .next: .next
        case .previous: .previous
        }
    }

    init?(_ command: NowPlayingCommand) {
        switch command {
        case .toggle: self = .toggle
        case .next: self = .next
        case .previous: self = .previous
        default: return nil
        }
    }
}

/// A transport button. The extension cannot reach the player, so it hands the command to the app.
struct NowPlayingControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Control Playback"
    static let isDiscoverable = false
    /// macOS redraws the widget when `perform` returns, and by then the player should have answered.
    private static let answerTime = Duration.milliseconds(800)

    @Parameter(title: "Action") var action: NowPlayingAction

    init() {}

    init(action: NowPlayingAction) {
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        try SnapshotStore().write(NowPlayingRequest(command: action.command), for: NowPlayingRequest.key)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(NowPlayingRequest.notificationName as CFString),
            nil,
            nil,
            true
        )
        try? await Task.sleep(for: Self.answerTime)
        return .result()
    }
}

/// The same entries as other widgets, plus the session. The system moves the progress bar by itself,
/// so a timeline only has to redraw at the end of the track and, for lyrics, at each new line.
struct NowPlayingProvider: TimelineProvider {
    let kind: WidgetKind
    private let store = SnapshotStore()
    private static let horizon: TimeInterval = 15 * 60
    private static let maxEntries = 60

    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(date: .now))
    }

    func getSnapshot(in _: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: snapshot()))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let current = snapshot()
        WidgetRefreshLog().record(kind: kind.rawValue, dataDate: current.date, at: now)
        let dates = [now] + changeDates(in: current, from: now)
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: current) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.horizon))))
    }

    private func snapshot() -> WidgetSnapshot {
        var snapshot = store.read(WidgetSnapshot.self, for: WidgetSnapshot.key) ?? WidgetSnapshot(date: .now)
        snapshot.nowPlaying = NowPlayingSnapshots(store: store).read()
        return snapshot
    }

    private func changeDates(in snapshot: WidgetSnapshot, from now: Date) -> [Date] {
        guard let session = snapshot.nowPlaying?.session, let end = session.endDate(from: now),
              let duration = session.track.duration
        else { return [] }
        guard kind == .lyrics else { return [end] }
        let position = session.position(at: now)
        let starts = session.lyricStarts.isEmpty
            ? LyricsTiming.lineStarts(in: session.lyrics, duration: duration)
            : session.lyricStarts
        return starts
            .filter { $0 > position }
            .map { now.addingTimeInterval($0 - position) }
            .filter { $0.timeIntervalSince(now) < Self.horizon }
            .prefix(Self.maxEntries) + [end]
    }
}

@MainActor
private func mediaConfiguration(_ kind: WidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: NowPlayingProvider(kind: kind)) { entry in
        KindView(kind: kind, entry: entry).environment(\.nowPlayingButton, NowPlayingButtonMaker { command, label in
            guard let action = NowPlayingAction(command) else { return label }
            return AnyView(Button(intent: NowPlayingControlIntent(action: action)) { label }.buttonStyle(.plain))
        })
    }
    .configurationDisplayName(kind.title)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
}

struct NowPlayingKindWidget: Widget {
    var body: some WidgetConfiguration {
        mediaConfiguration(.nowPlaying)
    }
}

struct LyricsKindWidget: Widget {
    var body: some WidgetConfiguration {
        mediaConfiguration(.lyrics)
    }
}
