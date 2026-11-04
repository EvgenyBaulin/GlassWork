import GlassWorkCore
import SwiftUI

/// Accent colors shared by panels, tiles, charts and widgets.
public enum Palette {
    public static let blue = Color(red: 0.231, green: 0.510, blue: 0.965)
    public static let green = Color(red: 0.357, green: 0.831, blue: 0.373)
    public static let purple = Color(red: 0.659, green: 0.333, blue: 0.969)
    public static let orange = Color(red: 0.961, green: 0.620, blue: 0.043)
    public static let red = Color(red: 0.937, green: 0.267, blue: 0.267)
    public static let cyan = Color(red: 0.431, green: 0.776, blue: 0.878)
    public static let yellow = Color(red: 0.961, green: 0.784, blue: 0.259)
    public static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)
    public static let teal = Color(red: 0.078, green: 0.722, blue: 0.651)
    public static let gray = Color(red: 0.557, green: 0.557, blue: 0.576)
}

/// Localized text from this package's string catalog.
public func loc(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}

public extension ModuleID {
    var title: String {
        switch self {
        case .overview: loc("Overview")
        case .cpu: loc("CPU")
        case .memory: loc("Memory")
        case .disk: loc("Disk")
        case .network: loc("Network")
        case .battery: loc("Battery")
        case .gpu: loc("GPU")
        case .sensors: loc("Sensors")
        case .fans: loc("Fans")
        case .uptime: loc("Uptime")
        case .aiUsage: loc("AI Usage")
        case .git: loc("Git")
        case .devServers: loc("Dev Servers")
        case .docker: loc("Docker")
        case .ping: loc("Ping")
        case .vpn: loc("VPN")
        case .wifi: loc("Wi-Fi")
        case .worldClocks: loc("World Clocks")
        case .timers: loc("Timers")
        case .keepAwake: loc("Keep Awake")
        case .nowPlaying: loc("Now Playing")
        case .notes: loc("Notes")
        case .countdown: loc("Countdown")
        case .stopwatch: loc("Stopwatch")
        case .colours: loc("Colours")
        case .appearance: loc("Appearance")
        case .eject: loc("Eject")
        case .sunMoon: loc("Sun and Moon")
        case .date: loc("Date")
        case .deviceBatteries: loc("Device Batteries")
        case .calendar: loc("Calendar")
        case .endsIn: loc("Ends In")
        case .todos: loc("To-Dos")
        case .weather: loc("Weather")
        case .rates: loc("Rates")
        case .clipboard: loc("Clipboard")
        default: rawValue
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "arrow.up.arrow.down"
        case .battery: "battery.75percent"
        case .gpu: "cube"
        case .sensors: "thermometer.medium"
        case .fans: "fan"
        case .uptime: "clock.arrow.circlepath"
        case .aiUsage: "sparkle"
        case .git: "arrow.triangle.branch"
        case .devServers: "server.rack"
        case .docker: "shippingbox"
        case .ping: "dot.radiowaves.left.and.right"
        case .vpn: "shield"
        case .wifi: "wifi"
        case .worldClocks: "globe"
        case .timers: "timer"
        case .keepAwake: "cup.and.heat.waves"
        case .nowPlaying: "music.note"
        case .notes: "note.text"
        case .countdown: "hourglass"
        case .stopwatch: "stopwatch"
        case .colours: "eyedropper"
        case .appearance: "circle.lefthalf.filled"
        case .eject: "eject"
        case .sunMoon: "sunrise"
        case .date, .calendar: "calendar"
        case .endsIn: "timer.circle"
        case .deviceBatteries: "battery.100percent.circle"
        case .todos: "checklist"
        case .weather: "cloud.sun"
        case .rates: "chart.line.uptrend.xyaxis"
        case .clipboard: "list.clipboard"
        default: "square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .overview, .uptime: Palette.gray
        case .cpu, .docker, .vpn, .wifi: Palette.blue
        case .aiUsage, .git: Palette.orange
        case .memory, .battery, .deviceBatteries, .devServers: Palette.green
        case .disk, .fans: Palette.cyan
        case .network, .ping: Palette.teal
        case .gpu: Palette.purple
        case .sensors, .date, .calendar, .endsIn: Palette.red
        case .todos: Palette.blue
        case .worldClocks: Palette.blue
        case .timers, .stopwatch, .sunMoon: Palette.orange
        case .notes: Palette.yellow
        case .countdown: Palette.purple
        case .colours, .nowPlaying: Palette.pink
        case .appearance: Palette.blue
        case .weather: Palette.cyan
        case .rates: Palette.green
        case .clipboard: Palette.teal
        default: Palette.gray
        }
    }

    /// Short label for the Labelled style, shown in tiny vertical capitals.
    var shortLabel: String {
        switch self {
        case .overview: "ALL"
        case .cpu: "CPU"
        case .memory: "MEM"
        case .disk: "SSD"
        case .network: "NET"
        case .battery: "BAT"
        case .gpu: "GPU"
        case .sensors: "TMP"
        case .fans: "FAN"
        case .uptime: "UP"
        case .aiUsage: "AI"
        case .git: "GIT"
        case .devServers: "DEV"
        case .docker: "CTR"
        case .ping: "PING"
        case .vpn: "VPN"
        case .wifi: "SIG"
        case .weather: "WTH"
        case .rates: "FX"
        case .nowPlaying: "NOW"
        case .clipboard: "CLP"
        default: ""
        }
    }

    /// Modules where a click does the job, so they have no panel.
    var isClickAction: Bool {
        self == .keepAwake || self == .stopwatch || self == .appearance
    }

    /// Modules that already have a collector and a panel.
    var isAvailable: Bool {
        switch self {
        case .overview, .cpu, .memory, .disk, .network, .battery, .gpu, .sensors, .uptime: true
        case .worldClocks, .timers, .keepAwake, .notes, .countdown, .stopwatch: true
        case .colours, .appearance, .eject, .sunMoon, .date: true
        case .aiUsage, .git, .devServers, .docker, .ping, .vpn, .wifi: true
        case .calendar, .endsIn, .todos, .deviceBatteries: true
        case .weather, .rates, .clipboard, .nowPlaying: true
        case .fans: FanHardware.hasFans
        default: false
        }
    }
}

public extension ModuleGroup {
    var title: String {
        switch self {
        case .system: loc("System")
        case .developer: loc("Developer")
        case .yourDay: loc("Your Day")
        case .everyday: loc("Everyday")
        case .extra: loc("Extra")
        }
    }
}

/// Rounded colored square with a white glyph.
public struct ModuleIcon: View {
    private let module: ModuleID
    private let size: CGFloat

    public init(_ module: ModuleID, size: CGFloat = 28) {
        self.module = module
        self.size = size
    }

    public var body: some View {
        Image(systemName: module.symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(module.tint.gradient, in: .rect(cornerRadius: size / 4))
    }
}
