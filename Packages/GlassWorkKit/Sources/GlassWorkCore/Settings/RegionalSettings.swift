import Foundation
import os

/// The language the app shows. `system` follows macOS.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, english, russian

    /// The value for `AppleLanguages`; nil for the system choice.
    public var languageCode: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .russian: "ru"
        }
    }

    public init(languageCode: String?) {
        self = Self.allCases.first { $0.languageCode == languageCode } ?? .system
    }
}

public enum TimeFormat: String, Codable, CaseIterable, Sendable {
    case system, twelveHour, twentyFourHour
}

public enum FirstWeekday: String, Codable, CaseIterable, Sendable {
    case system, monday, sunday

    /// `Calendar.firstWeekday`: 1 is Sunday, 2 is Monday.
    public var calendarValue: Int? {
        switch self {
        case .system: nil
        case .monday: 2
        case .sunday: 1
        }
    }
}

/// Language, clock and week overrides. All three default to following the Mac.
public struct RegionalSettings: Codable, Sendable, Equatable {
    public var language = AppLanguage.system
    public var timeFormat = TimeFormat.system
    public var firstWeekday = FirstWeekday.system

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case language, timeFormat, firstWeekday
    }

    /// A value this version does not know falls back to the system choice, one key at a time.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = (try? container.decodeIfPresent(AppLanguage.self, forKey: .language)) ?? .system
        timeFormat = (try? container.decodeIfPresent(TimeFormat.self, forKey: .timeFormat)) ?? .system
        firstWeekday = (try? container.decodeIfPresent(FirstWeekday.self, forKey: .firstWeekday)) ?? .system
    }

    /// `base` itself when nothing is overridden.
    public func locale(base: Locale = .current) -> Locale {
        let cycle: Locale.HourCycle
        switch timeFormat {
        case .system: return base
        case .twelveHour: cycle = .oneToTwelve
        case .twentyFourHour: cycle = .zeroToTwentyThree
        }
        var components = Locale.Components(locale: base)
        components.hourCycle = cycle
        return Locale(components: components)
    }

    /// `base` itself when nothing is overridden.
    public func calendar(base: Calendar = .current) -> Calendar {
        guard let value = firstWeekday.calendarValue else { return base }
        var calendar = base
        calendar.firstWeekday = value
        return calendar
    }
}

/// The settings the shared formatters read. The app sets them whenever the settings change.
public enum RegionalFormat {
    private static let state = OSAllocatedUnfairLock(initialState: RegionalSettings())

    public static var settings: RegionalSettings {
        state.withLock { $0 }
    }

    public static func apply(_ settings: RegionalSettings) {
        state.withLock { $0 = settings }
    }

    public static var locale: Locale {
        settings.locale()
    }

    public static var calendar: Calendar {
        settings.calendar()
    }
}
