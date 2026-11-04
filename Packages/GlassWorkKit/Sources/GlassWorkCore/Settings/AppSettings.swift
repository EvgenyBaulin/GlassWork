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

/// How the Hub lays out its tiles.
public struct HubSettings: Codable, Sendable, Equatable {
    public var isGrouped = true
    public var tileSize = PanelSize.medium
    public var showsMenuBarModules = true

    public init() {}

    /// Missing keys keep their defaults, so a hand edit of one key does not reset the others.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isGrouped = try container.decodeIfPresent(Bool.self, forKey: .isGrouped) ?? true
        tileSize = try container.decodeIfPresent(PanelSize.self, forKey: .tileSize) ?? .medium
        showsMenuBarModules = try container.decodeIfPresent(Bool.self, forKey: .showsMenuBarModules) ?? true
    }
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
    public var widgets = WidgetSettings()
    /// Lives here rather than in `widgets`, whose decoding fails on a key an older file does not have.
    public var personalWidgets = PersonalWidgetSettings()
    public var dock = DockSettings()
    public var weather = WeatherSettings()
    public var rates = RatesSettings()
    public var clipboard = ClipboardSettings()
    public var welcomeCompleted = false
    public var fans = FanSettings()
    public var windowTiles = WindowTilesSettings()
    public var hub = HubSettings()
    /// Off unless the user turns it on. See `DiagnosticLog`.
    public var keepsDiagnosticLog = false
    public var shortcuts = ShortcutSettings()

    public init(modules: [ModuleSettings] = AppSettings.defaultModules) {
        self.modules = modules
    }

    /// First launch: Overview, CPU and Memory in the menu bar, developer modules off, the rest in the Hub.
    public static var defaultModules: [ModuleSettings] {
        let developerCollected = ModuleID.developerCollected
        return ModuleID.allCases.map { id in
            switch id {
            case .overview: ModuleSettings(id: id, mode: .menuBar, style: .graphAndFigure)
            case .cpu: ModuleSettings(id: id, mode: .menuBar, style: .graphAndFigure)
            case .memory: ModuleSettings(id: id, mode: .menuBar, style: .labelled)
            case _ where developerCollected.contains(id): ModuleSettings(id: id, mode: .off, style: .figure)
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
        case version, modules, numberStyle, hiding, alerts, widgets, dock, weather, rates, clipboard, welcomeCompleted
        case fans, windowTiles, personalWidgets, hub, keepsDiagnosticLog, shortcuts
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
        widgets = try container.decodeIfPresent(WidgetSettings.self, forKey: .widgets) ?? WidgetSettings()
        dock = try container.decodeIfPresent(DockSettings.self, forKey: .dock) ?? DockSettings()
        weather = try container.decodeIfPresent(WeatherSettings.self, forKey: .weather) ?? WeatherSettings()
        rates = try container.decodeIfPresent(RatesSettings.self, forKey: .rates) ?? RatesSettings()
        clipboard = try container.decodeIfPresent(ClipboardSettings.self, forKey: .clipboard) ?? ClipboardSettings()
        welcomeCompleted = try container.decodeIfPresent(Bool.self, forKey: .welcomeCompleted) ?? false
        // A broken hand edit of the fan section must not cost the rest of the file.
        fans = (try? container.decodeIfPresent(FanSettings.self, forKey: .fans)) ?? FanSettings()
        windowTiles = (try? container.decodeIfPresent(WindowTilesSettings.self, forKey: .windowTiles))
            ?? WindowTilesSettings()
        personalWidgets = (try? container.decodeIfPresent(PersonalWidgetSettings.self, forKey: .personalWidgets))
            ?? PersonalWidgetSettings()
        hub = (try? container.decodeIfPresent(HubSettings.self, forKey: .hub)) ?? HubSettings()
        keepsDiagnosticLog = try container.decodeIfPresent(Bool.self, forKey: .keepsDiagnosticLog) ?? false
        shortcuts = (try? container.decodeIfPresent(ShortcutSettings.self, forKey: .shortcuts)) ?? ShortcutSettings()
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
