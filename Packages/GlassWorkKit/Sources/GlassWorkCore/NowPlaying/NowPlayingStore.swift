import Foundation
import Observation

/// The current session, and the adapter that reports it.
@MainActor
@Observable
public final class NowPlayingStore {
    public private(set) var session: NowPlayingSession?
    public private(set) var artwork: Data?
    /// False until the adapter has answered, so nothing claims "nothing playing" before it knows.
    public private(set) var hasLoaded = false
    /// macOS refused the adapter, so restarting it would not help.
    public private(set) var isUnavailable = false
    public var outputDevice: String?

    /// Called when a widget would look different. Position reports alone do not count.
    @ObservationIgnored public var onChange: (() -> Void)?
    /// The same moments, for the menu bar. VLC reports every second, which must not redraw every item.
    @ObservationIgnored public var onUpdate: (() -> Void)?

    @ObservationIgnored private let makeSource: @Sendable () -> NowPlayingSource?
    @ObservationIgnored private let appName: @MainActor (String) -> String?
    @ObservationIgnored private var appNames: [String: String] = [:]
    @ObservationIgnored private var source: NowPlayingSource?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retryAt = Date.distantPast
    @ObservationIgnored private var keepRunningUntil = Date.distantPast
    @ObservationIgnored private var generation = 0

    private static let unavailableStatus: Int32 = 3
    private static let longestRetry: TimeInterval = 300
    /// A command from a widget can arrive when nothing else needs the adapter.
    private static let commandGrace: TimeInterval = 15

    /// `appName` names an app from its bundle identifier. Browsers report a helper process otherwise.
    public init(
        makeSource: @escaping @Sendable () -> NowPlayingSource? = { nil },
        appName: @escaping @MainActor (String) -> String? = { _ in nil }
    ) {
        self.makeSource = makeSource
        self.appName = appName
    }

    public var isRunning: Bool {
        source != nil
    }

    /// Runs with the monitor's loop: starts the adapter when something needs it and ends it when nothing does.
    public func tick(wanted: Bool, at date: Date) {
        if wanted || date < keepRunningUntil {
            start(at: date)
        } else {
            stop()
        }
    }

    /// Ends the adapter. It starts again on the next tick if it is still needed.
    ///
    /// What it last said may no longer be true by then, so that goes too. The widgets' file stays:
    /// a Mac going to sleep is no reason to redraw them.
    public func stop() {
        guard let running = source else { return }
        generation += 1
        source = nil
        running.stop()
        session = nil
        artwork = nil
        hasLoaded = false
    }

    public func perform(_ command: NowPlayingCommand, at date: Date = Date()) {
        keepRunningUntil = date.addingTimeInterval(Self.commandGrace)
        start(at: date)
        source?.send(command.line)
    }

    private func start(at date: Date) {
        guard source == nil, !isUnavailable, date >= retryAt, let next = makeSource() else { return }
        generation += 1
        let current = generation
        do {
            try next.start(
                onLine: { [weak self] line in
                    Task { @MainActor in self?.receive(line, generation: current) }
                },
                onExit: { [weak self] status in
                    Task { @MainActor in self?.exited(status, generation: current, at: Date()) }
                }
            )
            source = next
        } catch {
            failed(at: date)
        }
    }

    private func receive(_ line: String, generation current: Int) {
        guard current == generation, let event = NowPlayingParser.parse(line) else { return }
        apply(event)
    }

    /// Takes one adapter line, as if it had just been printed.
    public func apply(_ event: NowPlayingEvent) {
        failures = 0
        switch event {
        case let .session(reported):
            let old = session
            let new = reported.map(named)
            session = new
            hasLoaded = true
            if new?.artworkID != old?.artworkID {
                artwork = nil
            }
            if isDifferent(old, new) {
                changed()
            }
        case let .artwork(id, data):
            guard id == session?.artworkID else { return }
            artwork = ArtworkImage.fitted(data)
            changed()
        case .unavailable:
            isUnavailable = true
            hasLoaded = true
            changed()
        }
    }

    private func changed() {
        onChange?()
        onUpdate?()
    }

    private func named(_ session: NowPlayingSession) -> NowPlayingSession {
        guard let id = session.bundleID else { return session }
        if appNames[id] == nil {
            appNames[id] = appName(id)
        }
        var named = session
        named.appName = appNames[id] ?? session.appName
        return named
    }

    private func isDifferent(_ old: NowPlayingSession?, _ new: NowPlayingSession?) -> Bool {
        guard let old, let new else { return old != nil || new != nil }
        return new.looksDifferent(from: old)
    }

    private func exited(_ status: Int32, generation current: Int, at date: Date) {
        guard current == generation else { return }
        source = nil
        if status == Self.unavailableStatus {
            isUnavailable = true
            hasLoaded = true
        } else {
            failed(at: date)
        }
    }

    /// Waits longer after each crash, so a broken script does not spin.
    private func failed(at date: Date) {
        failures += 1
        retryAt = date.addingTimeInterval(min(5 * pow(2, Double(failures - 1)), Self.longestRetry))
    }
}

public extension NowPlayingStore {
    /// What desktop widgets show.
    var widgetData: NowPlayingWidgetData? {
        session.map { NowPlayingWidgetData(session: $0, artwork: artwork, outputDevice: outputDevice) }
    }
}
