import Foundation

/// A value snapshot. Nil readings mean unavailable, rather than disconnected or empty.
public struct IslandInput: Sendable, Equatable {
    public var calendarEvents: [AgendaEvent] = []
    public var timers: [CountdownTimer] = []
    public var sensors: SensorSample?
    public var processes: [ProcessUsage] = []
    public var volumes: [DiskVolume] = []
    public var alerts = AlertSettings()
    /// No shared disk alert threshold exists. Decimal bytes match Finder's capacity units.
    public var lowSpaceBytes: UInt64 = 10_000_000_000
    public var wifi: WiFiReading?
    public var vpn: VPNReading?
    public var ping: PingOutcome?
    public var previousPing: PingOutcome?
    public var pingHost: String?
    public var docker: DockerReading?
    public var devServers: DevServerReading?
    public var battery: BatterySample?
    public var isKeepingAwake = false
    public var keepAwakeEnds: Date?
    public var keepAwakeIncludesDisplay: Bool?
    public var nowPlaying: NowPlayingSession?
    public var clipboardEntry: ClipboardEntry?
    public var artwork: Data?
    public var outputDevice: String?
    /// The caller supplies a thumbnail; building events never reads the history folder.
    public var clipboardPreview: Data?
    public var clipboardImageURL: URL?
    /// Filled by the host, which listens for changes; nil when it does not.
    public var levels: SystemLevels?

    public init() {}

    /// Copies existing readings without initiating screen access, sampling or permission requests.
    @MainActor
    public init(monitor: SystemMonitor, alerts: AlertSettings = AlertSettings()) {
        calendarEvents = monitor.agenda.events
        timers = monitor.everyday.data.timers
        sensors = monitor.sensors
        processes = monitor.processes
        volumes = monitor.volumes
        self.alerts = alerts
        wifi = monitor.developer.wifi
        vpn = monitor.developer.vpn
        ping = monitor.developer.ping.latest?.outcome
        previousPing = monitor.developer.ping.samples.dropLast().last?.outcome
        pingHost = monitor.developer.options.pingHost
        docker = monitor.developer.docker
        devServers = monitor.developer.devServers
        battery = monitor.battery
        isKeepingAwake = monitor.everyday.isKeepingAwake
        keepAwakeEnds = monitor.everyday.keepAwakeEnds
        keepAwakeIncludesDisplay = !monitor.everyday.letsDisplaySleep
        nowPlaying = monitor.nowPlaying.session
        artwork = monitor.nowPlaying.artwork
        outputDevice = monitor.nowPlaying.outputDevice
        clipboardEntry = monitor.clipboard.history.entries.first
        clipboardImageURL = clipboardEntry.flatMap { monitor.clipboard.imageURL(for: $0) }
    }
}
