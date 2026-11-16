import Foundation

public enum IslandEventKind: String, CaseIterable, Sendable {
    case meeting, inProgress, timers, systemAlert, network, devServers, charging
    case keepAwake, nowPlaying, weather, copied
    case downloads, airPods, volume, agents

    public var importance: Int {
        Self.allCases.firstIndex(of: self)!
    }
}

public enum IslandNetworkDetail: Sendable, Equatable {
    case wifiLost(WiFiReading)
    case vpnOff(VPNReading)
    case pingRecovered(PingOutcome)
}

public enum IslandDeveloperDetail: Sendable, Equatable {
    case containerExited(DockerContainer)
    case serverAppeared(DevServer)
}

public struct IslandSystemAlert: Sendable, Equatable {
    public var averageCPU: Double?
    public var topProcess: ProcessUsage?
    public var lowSpaceVolume: DiskVolume?

    public init(averageCPU: Double?, topProcess: ProcessUsage?, lowSpaceVolume: DiskVolume?) {
        self.averageCPU = averageCPU
        self.topProcess = topProcess
        self.lowSpaceVolume = lowSpaceVolume
    }
}

public enum IslandDetail: Sendable, Equatable {
    case meeting(AgendaEvent)
    case inProgress(AgendaEvent)
    /// End dates preserve remaining time and overrun; paused timers retain their remaining duration.
    case timers([CountdownTimer])
    case systemAlert(IslandSystemAlert)
    case network(IslandNetworkDetail)
    case devServers(IslandDeveloperDetail)
    case charging(BatterySample)
    /// Only GlassWork's own mode, with its scheduled end.
    case keepAwake(endsAt: Date)
    case nowPlaying(NowPlayingSession)
    case weather(WeatherReport)
    case copied(ClipboardEntry)
}

public struct IslandEvent: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: IslandEventKind
    public var since: Date
    public var expires: Date?
    public var context = IslandContext()
    public var detail: IslandDetail

    public init(id: String, kind: IslandEventKind, since: Date, expires: Date? = nil, detail: IslandDetail) {
        self.id = id
        self.kind = kind
        self.since = since
        self.expires = expires
        self.detail = detail
    }

    /// Transition alerts survive subsequent snapshots until expiry, recovery or dismissal.
    var isTransition: Bool {
        switch detail {
        case .network, .devServers, .charging, .copied: true
        default: false
        }
    }
}
