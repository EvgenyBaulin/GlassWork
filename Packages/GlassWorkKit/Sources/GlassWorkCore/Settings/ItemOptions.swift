import Foundation

/// Reading `ModuleSettings.options`. A missing or unreadable entry means the default, so defaults are never stored.
public extension [String: String] {
    func flag(_ key: String, default fallback: Bool) -> Bool {
        self[key].map { $0 == "true" } ?? fallback
    }

    func number(_ key: String, default fallback: Int) -> Int {
        self[key].flatMap { Int($0) } ?? fallback
    }

    func choice<Choice: RawRepresentable>(_ key: String, default fallback: Choice) -> Choice
        where Choice.RawValue == String
    {
        self[key].flatMap(Choice.init(rawValue:)) ?? fallback
    }
}

/// Keys of the options the Settings rows write.
public enum ItemOption {
    public static let showsCPU = "showCPU"
    public static let showsMemory = "showMemory"
    public static let showsDisk = "showDisk"
    public static let splitsUserSystem = "splitUserSystem"
    public static let topApps = "topApps"
    public static let samplingSeconds = "samplingSeconds"
    public static let slowsOnBattery = "slowsOnBattery"
    public static let highlightAbove = "highlightAbove"
    public static let memoryFigure = "showAs"
    public static let showsSwap = "showSwap"
    public static let colorsByPressure = "colourByPressure"
    public static let diskFigure = "diskShows"
    public static let rateUnit = "units"
    public static let networkDirection = "direction"
    public static let hideBelow = "hideBelow"
    public static let batteryFigure = "batteryShows"
    public static let hidesWhenFull = "hideWhenFull"
    public static let lowPercent = "lowPercent"
    public static let warnAbove = "warnAbove"
    public static let temperatureUnit = "temperatureUnit"
    public static let networkInterface = "interface"
    public static let gpuName = "gpu"
    public static let volumePath = "volume"
    public static let showsUnknownSensors = "unknownSensors"
    public static let uptimeFormat = "uptimeFormat"
    public static let calendarWindowHours = "windowHours"
    public static let skipsAllDay = "skipAllDay"
    public static let titleLength = "titleLength"
    public static let includesAllDay = "includeAllDay"
    public static let warnMinutes = "warnMinutes"
    public static let showsFree = "showFree"
    public static let showsSeconds = "showSeconds"
    public static let timerPresets = "presets"
    public static let letsDisplaySleep = "letDisplaySleep"
    public static let keepAwakeMinutes = "defaultMinutes"
    public static let keepAwakeBatteryFloor = "batteryFloor"
    public static let timerSound = "sound"
    public static let timerNotifies = "notify"
    public static let ejectAsksFirst = "askBeforeEjectAll"
    public static let ejectIncludesImages = "includeDiskImages"
    public static let ejectIncludesNetwork = "includeNetworkVolumes"
    public static let ejectNever = "neverEject"
    public static let countsServices = "countServices"
    public static let todoSort = "sort"
    public static let todoCompleted = "completed"
    public static let panelSize = "panelSize"
    public static let notesFont = "font"
    public static let hidesWhenDone = "hideWhenDone"
    public static let colourFormat = "copyAs"
    public static let colourUppercase = "uppercase"
    public static let colourHash = "includeHash"
    public static let colourLimit = "remember"
    public static let warnBelow = "warnBelow"
    public static let dateFigure = "dateFormat"
    public static let datePattern = "datePattern"
    public static let showsWeek = "showWeek"
    public static let weekNumbering = "weekNumbering"
    public static let dockerCount = "count"
    public static let onlyWhenConnected = "onlyWhenConnected"
    public static let greenWhenConnected = "greenWhenConnected"
    public static let warnMilliseconds = "warnMilliseconds"
    public static let weakSignal = "weakSignal"
    public static let sunPlace = "place"
    public static let sunShows = "shows"
}

public enum MemoryFigure: String, Sendable, CaseIterable {
    case share, gigabytes, pressure
}

public enum DiskFigure: String, Sendable, CaseIterable {
    case free, activity, both
}

public enum RateUnit: String, Sendable, CaseIterable {
    case bytes, bits
}

public enum NetworkDirection: String, Sendable, CaseIterable {
    case both, download, upload
}

public enum BatteryFigure: String, Sendable, CaseIterable {
    case charge, timeLeft
}

public enum DockerCount: String, Sendable, CaseIterable {
    case running, all
}

public enum PanelSize: String, Codable, Sendable, CaseIterable {
    case small, medium, large

    /// Height of the text area in the Notes panel.
    public var noteHeight: Double {
        switch self {
        case .small: 120
        case .medium: 200
        case .large: 320
        }
    }
}

public enum NotesFont: String, Sendable, CaseIterable {
    case system, mono
}

public enum UptimeFormat: String, Sendable, CaseIterable {
    case compact, days, hours

    /// `76:12`: hours and minutes.
    public static func hoursText(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval)) / 60
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    public static func wholeDays(_ interval: TimeInterval) -> Int {
        max(0, Int(interval)) / 86400
    }
}

public enum ColourFormat: String, Sendable, CaseIterable {
    case hex, rgb, hsl

    /// What the Colours module copies. `hex` is `#RRGGBB`; anything else comes back unchanged.
    public func text(hex: String, isUppercase: Bool, hasHash: Bool) -> String {
        guard let value = UInt32(hex.dropFirst(), radix: 16), hex.count == 7 else { return hex }
        let red = Int(value >> 16 & 0xFF)
        let green = Int(value >> 8 & 0xFF)
        let blue = Int(value & 0xFF)
        switch self {
        case .hex:
            let digits = hex.dropFirst()
            return (hasHash ? "#" : "") + (isUppercase ? digits.uppercased() : digits.lowercased())
        case .rgb:
            return "rgb(\(red), \(green), \(blue))"
        case .hsl:
            let hsl = HSL(red: red, green: green, blue: blue)
            return "hsl(\(hsl.hue), \(hsl.saturation)%, \(hsl.lightness)%)"
        }
    }
}

/// Hue in degrees, the other two in percent.
private struct HSL {
    let hue: Int
    let saturation: Int
    let lightness: Int

    init(red: Int, green: Int, blue: Int) {
        let parts = [red, green, blue].map { Double($0) / 255 }
        let high = parts.max() ?? 0
        let low = parts.min() ?? 0
        let delta = high - low
        let middle = (high + low) / 2
        lightness = Int((middle * 100).rounded())
        guard delta > 0 else {
            hue = 0
            saturation = 0
            return
        }
        saturation = Int((delta / (1 - abs(2 * middle - 1)) * 100).rounded())
        let sector = if high == parts[0] {
            ((parts[1] - parts[2]) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == parts[1] {
            (parts[2] - parts[0]) / delta + 2
        } else {
            (parts[0] - parts[1]) / delta + 4
        }
        hue = Int(((sector * 60 + 360).truncatingRemainder(dividingBy: 360)).rounded())
    }
}

public enum DateFigure: String, Sendable, CaseIterable {
    case weekdayDayMonth, dayMonth, numeric, custom
}

public enum WeekNumbering: String, Sendable, CaseIterable {
    case iso, system
}

/// The text of the Date module.
public struct DateItemText: Sendable {
    public var figure = DateFigure.weekdayDayMonth
    public var pattern = ""
    public var showsWeek = false
    public var numbering = WeekNumbering.iso
    public var locale = Locale.current
    public var timeZone = TimeZone.current

    public init() {}

    public init(options: [String: String]) {
        figure = options.choice(ItemOption.dateFigure, default: .weekdayDayMonth)
        pattern = options[ItemOption.datePattern] ?? ""
        showsWeek = options.flag(ItemOption.showsWeek, default: false)
        numbering = options.choice(ItemOption.weekNumbering, default: .iso)
    }

    public func text(for date: Date) -> String {
        let base = dayText(for: date)
        return showsWeek ? "\(base) · W\(week(of: date))" : base
    }

    public func week(of date: Date) -> Int {
        var calendar = numbering == .iso ? Calendar(identifier: .iso8601) : Calendar.current
        calendar.timeZone = timeZone
        return calendar.component(.weekOfYear, from: date)
    }

    private func dayText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        switch figure {
        case .weekdayDayMonth: formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        case .dayMonth: formatter.setLocalizedDateFormatFromTemplate("d MMM")
        case .numeric: formatter.setLocalizedDateFormatFromTemplate("dd MM yyyy")
        case .custom:
            // An empty field while typing must not leave the menu bar item blank.
            if pattern.isEmpty {
                formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
            } else {
                formatter.dateFormat = pattern
            }
        }
        return formatter.string(from: date)
    }
}

/// The lengths Timers offers. Text, so it can be edited in one field: `1, 5, 10, 25, 60`.
public enum TimerPresets {
    public static let standard = [1, 3, 5, 10, 15, 25, 30, 60]

    /// Whole minutes from a day at most, in the order typed. Nothing usable means the standard list.
    public static func parse(_ text: String?) -> [Int] {
        let parts = (text ?? "").split { !$0.isNumber }.compactMap { Int($0) }
        var seen = Set<Int>()
        let minutes = parts.filter { (1 ... 1440).contains($0) && seen.insert($0).inserted }
        return minutes.isEmpty ? standard : minutes
    }
}

/// The next event worth showing in the Calendar module.
public enum CalendarItem {
    public static func next(
        in events: [AgendaEvent],
        at date: Date,
        windowHours: Int,
        skipsAllDay: Bool
    ) -> AgendaEvent? {
        guard let next = EndsInState(events: events, at: date, includeAllDay: !skipsAllDay).next else { return nil }
        let limit = date.addingTimeInterval(TimeInterval(windowHours) * 3600)
        return windowHours > 0 && next.start > limit ? nil : next
    }

    /// Cut to `limit` characters, the last of them an ellipsis.
    public static func title(_ text: String, limit: Int) -> String {
        text.count > limit ? "\(text.prefix(max(limit - 1, 1)))…" : text
    }
}
