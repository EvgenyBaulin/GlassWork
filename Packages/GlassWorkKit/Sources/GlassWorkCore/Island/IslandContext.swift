import Foundation

/// Related readings available to an expanded card. Missing values stay hidden.
public struct IslandContext: Sendable, Equatable {
    public var nextEvent: AgendaEvent?
    public var fanRPM: Double?
    public var isOverheated = false
    public var vpn: VPNReading?
    public var ping: PingOutcome?
    public var previousPing: PingOutcome?
    public var pingHost: String?
    public var keepAwakeIncludesDisplay: Bool?
    public var servers: [DevServer] = []
    public var dockerContext: String?
    public var artwork: Data?
    public var outputDevice: String?
    public var clipboardPreview: Data?
    public var clipboardImageURL: URL?

    public init() {}

    public init(input: IslandInput, now: Date) {
        nextEvent = EndsInState(events: input.calendarEvents, at: now).next
        fanRPM = input.sensors?.fans.map(\.rpm).max()
        isOverheated = input.sensors?.averageCPU.map { $0 >= Double(input.alerts.highTemperature) } ?? false
        vpn = input.vpn
        ping = input.ping
        previousPing = input.previousPing
        pingHost = input.pingHost
        keepAwakeIncludesDisplay = input.keepAwakeIncludesDisplay
        servers = input.devServers?.servers ?? []
        if case let .containers(_, context) = input.docker {
            dockerContext = context
        }
        artwork = input.artwork
        outputDevice = input.outputDevice
        clipboardPreview = input.clipboardPreview
        clipboardImageURL = input.clipboardImageURL
    }
}
