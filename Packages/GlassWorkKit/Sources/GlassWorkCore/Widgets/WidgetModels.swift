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
    case digitalClock, modularClock, calendarMonth, upNext, endsIn, todo, note, timer, countdown, yearInDots, moon,
         daylight

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

    public init() {}
}
