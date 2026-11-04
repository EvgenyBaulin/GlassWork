import Foundation

public enum WidgetSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    /// Points, as macOS draws widgets.
    public var width: Double {
        switch self {
        case .small: 170
        case .medium, .large: 364
        case .extraLarge: 760
        }
    }

    public var height: Double {
        switch self {
        case .small, .medium: 170
        case .large, .extraLarge: 382
        }
    }
}

/// Every desktop widget. The raw value is stored in settings and used as the WidgetKit kind.
public enum WidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case activity, battery, macHealth, storage, temperature, topApps, network
    /// Kept under its first identifier so widgets already on the desktop keep working.
    case uptime = "io.github.evgenybaulin.glasswork.uptime"
    case screenTime, commands, endpoints, githubReviews, githubActions, contributions
    case digitalClock, modularClock, calendarMonth, upNext, endsIn, todo, note, timer, countdown, yearInDots, moon,
         daylight
    case clock, numeralsClock, minimalClock, flipClock, skyClock, dayAndNight
    case weekend, progress, stopwatch, pomodoro, focusTime, wordOfDay
    case fans, weather, rates, git, devServers, containers, aiUsage
    case devices, wifiSignal, diskActivity, timeMachine
    case screenTimeWeek, categories, breaks, appTime, mostUsed

    public var id: String {
        rawValue
    }
}

/// Everything widgets show, written by the app into the shared container.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public static let key = "widgets"

    public var date: Date
    public var cpu: CPUSample?
    public var cpuInfo: CPUInfo?
    public var memory: MemorySample?
    public var gpu: GPUSample?
    public var battery: BatterySample?
    public var volumes: [DiskVolume] = []
    public var network: NetworkSample?
    public var sensors: SensorSample?
    public var processes: [ProcessUsage] = []
    public var everyday = EverydayData()
    public var events: [AgendaEvent] = []
    public var todos: [TodoItem] = []
    public var bootTime: Date?
    public var screenTime = ScreenTimeLog()
    public var commands: [UserCommand] = []
    public var commandResults: [UUID: CommandResult] = [:]
    public var endpoints: [Endpoint] = []
    public var endpointChecks: [UUID: [EndpointCheck]] = [:]
    public var reviews: [PullRequest] = []
    public var runs: [WorkflowRun] = []
    public var contributions: [ContributionDay] = []
    /// The first weather place, used by the sun-based clocks; nil until one is saved.
    public var place: WeatherPlace?
    /// Today's word first, then the days before.
    public var words: [WordOfDay] = []
    /// Optional so a snapshot written by an earlier version still decodes until the next refresh.
    public var fans: WidgetFanState?
    /// Each fan's speed over the last ten minutes.
    public var fanHistory: [Int: [History<Double>.Point]]?
    public var diskActivity: DiskActivity?
    /// The last minute, sampled finely.
    public var diskMinute: WidgetDiskHistory?
    /// The last five minutes, averaged.
    public var diskLonger: WidgetDiskHistory?
    public var weather: WidgetWeather?
    public var rates: WidgetRates?
    public var git: GitReading?
    public var devServers: DevServerReading?
    public var docker: DockerReading?
    public var aiUsage: AIUsageReading?
    public var wifi: WiFiReading?
    /// Signal over the last ten minutes, on `WiFiSignal`'s scale.
    public var wifiHistory: [History<Double>.Point]?
    public var devices: [DeviceBattery]?
    public var timeMachine: TimeMachineStatus?

    public init(date: Date) {
        self.date = date
    }
}

/// A widget placed on the desktop as GlassWork's own window.
public struct WidgetPlacement: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var kind: WidgetKind
    public var size: WidgetSize
    public var x: Double
    public var y: Double
    public var isLocked = false

    public init(kind: WidgetKind, size: WidgetSize, x: Double, y: Double) {
        self.kind = kind
        self.size = size
        self.x = x
        self.y = y
    }

    /// Grid step: the small widget plus the gap macOS leaves between widgets.
    public static let gridStep = 170.0 + 24.0

    public static func snapped(_ value: Double) -> Double {
        (value / gridStep).rounded() * gridStep
    }
}

/// Floating widgets and how WidgetKit widgets refresh.
public struct WidgetSettings: Codable, Sendable, Equatable {
    public var placements: [WidgetPlacement] = []
    /// One arrangement per set of connected displays.
    public var layouts: [String: [WidgetPlacement]] = [:]
    public var refreshSeconds = 60
    public var glassDensity = 0.0
    public var tracksScreenTime = false
    public var commands: [UserCommand] = []
    public var endpoints: [Endpoint] = []

    public init() {}
}
