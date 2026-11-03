import Foundation

public enum ModuleGroup: String, Codable, CaseIterable, Sendable {
    case system, developer, yourDay, everyday, extra
}

/// Every menu bar module. The raw value is stored in settings.json, so it must not change.
public enum ModuleID: String, Codable, CaseIterable, Sendable, Identifiable {
    case overview, cpu, memory, disk, network, battery, gpu, sensors, fans
    case aiUsage, git, devServers, docker, ping, vpn, wifi, uptime
    case calendar, worldClocks, timers, keepAwake, nowPlaying, endsIn
    case notes, todos, countdown, stopwatch, shelf, colours, appearance
    case deviceBatteries, eject, sunMoon, date, clipboard
    case weather, rates

    public var id: String {
        rawValue
    }

    public var group: ModuleGroup {
        switch self {
        case .overview, .cpu, .memory, .disk, .network, .battery, .gpu, .sensors, .fans: .system
        case .aiUsage, .git, .devServers, .docker, .ping, .vpn, .wifi, .uptime: .developer
        case .calendar, .worldClocks, .timers, .keepAwake, .nowPlaying, .endsIn: .yourDay
        case .weather, .rates: .extra
        default: .everyday
        }
    }
}

public enum ModuleMode: String, Codable, CaseIterable, Sendable {
    case menuBar, hubOnly, off
}

public enum DisplayStyle: String, Codable, CaseIterable, Sendable {
    case symbol, figure, graph, graphAndFigure, labelled
}

public enum NumberStyle: String, Codable, CaseIterable, Sendable {
    case compact, precise
}

public struct ModuleSettings: Codable, Sendable, Equatable, Identifiable {
    public var id: ModuleID
    public var mode: ModuleMode
    public var style: DisplayStyle
    /// Module-specific choices, such as which sensor the item shows.
    public var options: [String: String]

    public init(id: ModuleID, mode: ModuleMode, style: DisplayStyle, options: [String: String] = [:]) {
        self.id = id
        self.mode = mode
        self.style = style
        self.options = options
    }
}

public struct HidingSettings: Codable, Sendable, Equatable {
    public var isEnabled = false
    public var autoHideSeconds = 10

    public init() {}
}

/// Threshold notifications. macOS asks for permission when these are first turned on.
public struct AlertSettings: Codable, Sendable, Equatable {
    public var isEnabled = false
    public var lowBatteryPercent = 10
    public var highTemperature = 95

    public init() {}
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var version = 1
    public var modules: [ModuleSettings]
    public var numberStyle: NumberStyle = .compact
    public var hiding = HidingSettings()
    public var alerts = AlertSettings()
    public var welcomeCompleted = false

    public init(modules: [ModuleSettings] = AppSettings.defaultModules) {
        self.modules = modules
    }

    /// First launch: Overview, CPU and Memory in the menu bar, everything else in the Hub.
    public static var defaultModules: [ModuleSettings] {
        ModuleID.allCases.map { id in
            switch id {
            case .overview: ModuleSettings(id: id, mode: .menuBar, style: .graphAndFigure)
            case .cpu: ModuleSettings(id: id, mode: .menuBar, style: .graphAndFigure)
            case .memory: ModuleSettings(id: id, mode: .menuBar, style: .labelled)
            default: ModuleSettings(id: id, mode: .hubOnly, style: .figure)
            }
        }
    }

    public func module(_ id: ModuleID) -> ModuleSettings? {
        modules.first { $0.id == id }
    }

    public mutating func update(_ id: ModuleID, _ change: (inout ModuleSettings) -> Void) {
        guard let index = modules.firstIndex(where: { $0.id == id }) else { return }
        change(&modules[index])
    }

    /// Adds modules introduced after the file was written and drops unknown ones.
    public mutating func normalize() {
        let known = Set(modules.map(\.id))
        modules += AppSettings.defaultModules.filter { !known.contains($0.id) }
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case version, modules, numberStyle, hiding, alerts, welcomeCompleted
    }

    /// Missing keys fall back to defaults so hand-edited files keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(modules: container.decodeIfPresent([LossyModule].self, forKey: .modules)?
            .compactMap(\.value) ?? AppSettings.defaultModules)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        numberStyle = try container.decodeIfPresent(NumberStyle.self, forKey: .numberStyle) ?? .compact
        hiding = try container.decodeIfPresent(HidingSettings.self, forKey: .hiding) ?? HidingSettings()
        alerts = try container.decodeIfPresent(AlertSettings.self, forKey: .alerts) ?? AlertSettings()
        welcomeCompleted = try container.decodeIfPresent(Bool.self, forKey: .welcomeCompleted) ?? false
        normalize()
    }

    /// An entry for a module this version does not know is skipped instead of failing the file.
    private struct LossyModule: Decodable {
        let value: ModuleSettings?

        init(from decoder: Decoder) throws {
            value = try? ModuleSettings(from: decoder)
        }
    }
}
