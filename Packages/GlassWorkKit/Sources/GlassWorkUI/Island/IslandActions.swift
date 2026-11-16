import Foundation
import GlassWorkCore

/// Commands supplied by the host; views never perform system operations themselves.
@MainActor
public struct IslandActions {
    public var joinMeeting: (URL) -> Void
    public var snooze: () -> Void
    public var runningLate: () -> Void
    public var addMinute: () -> Void
    public var stopTimers: () -> Void
    public var addTimer: () -> Void
    public var pin: (UUID) -> Void
    public var openHistory: () -> Void
    public var fansToMax: () -> Void
    public var openActivityMonitor: () -> Void
    public var showTop: () -> Void
    public var reconnectVPN: () -> Void
    public var openNetworkSettings: () -> Void
    public var restartContainer: (String) -> Void
    public var containerLogs: (String) -> Void
    public var openURL: (URL) -> Void
    public var playPause: () -> Void
    public var next: () -> Void
    public var previous: () -> Void
    public var seek: (TimeInterval) -> Void
    public var setVolume: (Double) -> Void
    public var extendKeepAwake: (TimeInterval) -> Void
    public var stopKeepAwake: () -> Void
    public var dismiss: (String) -> Void
    public var openPage: (Int) -> Void

    public init(
        joinMeeting: @escaping (URL) -> Void = { _ in },
        snooze: @escaping () -> Void = {},
        runningLate: @escaping () -> Void = {},
        addMinute: @escaping () -> Void = {},
        stopTimers: @escaping () -> Void = {},
        addTimer: @escaping () -> Void = {},
        pin: @escaping (UUID) -> Void = { _ in },
        openHistory: @escaping () -> Void = {},
        fansToMax: @escaping () -> Void = {},
        openActivityMonitor: @escaping () -> Void = {},
        showTop: @escaping () -> Void = {},
        reconnectVPN: @escaping () -> Void = {},
        openNetworkSettings: @escaping () -> Void = {},
        restartContainer: @escaping (String) -> Void = { _ in },
        containerLogs: @escaping (String) -> Void = { _ in },
        openURL: @escaping (URL) -> Void = { _ in },
        playPause: @escaping () -> Void = {},
        next: @escaping () -> Void = {},
        previous: @escaping () -> Void = {},
        seek: @escaping (TimeInterval) -> Void = { _ in },
        setVolume: @escaping (Double) -> Void = { _ in },
        extendKeepAwake: @escaping (TimeInterval) -> Void = { _ in },
        stopKeepAwake: @escaping () -> Void = {},
        dismiss: @escaping (String) -> Void = { _ in },
        openPage: @escaping (Int) -> Void = { _ in }
    ) {
        self.joinMeeting = joinMeeting
        self.snooze = snooze
        self.runningLate = runningLate
        self.addMinute = addMinute
        self.stopTimers = stopTimers
        self.addTimer = addTimer
        self.pin = pin
        self.openHistory = openHistory
        self.fansToMax = fansToMax
        self.openActivityMonitor = openActivityMonitor
        self.showTop = showTop
        self.reconnectVPN = reconnectVPN
        self.openNetworkSettings = openNetworkSettings
        self.restartContainer = restartContainer
        self.containerLogs = containerLogs
        self.openURL = openURL
        self.playPause = playPause
        self.next = next
        self.previous = previous
        self.seek = seek
        self.setVolume = setVolume
        self.extendKeepAwake = extendKeepAwake
        self.stopKeepAwake = stopKeepAwake
        self.dismiss = dismiss
        self.openPage = openPage
    }

    func perform(_ command: NowPlayingCommand) {
        switch command {
        case .play, .pause, .toggle: playPause()
        case .next: next()
        case .previous: previous()
        case let .seek(seconds): seek(seconds)
        }
    }
}
