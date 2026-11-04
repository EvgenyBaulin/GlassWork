import Foundation

/// Kinds of app, from the category each app declares for the App Store.
public enum AppCategory: String, Codable, CaseIterable, Sendable {
    case development, productivity, communication, entertainment, other

    /// Reads `LSApplicationCategoryType`.
    public init(appStoreCategory: String?) {
        switch appStoreCategory?.replacing("public.app-category.", with: "") {
        case "developer-tools": self = .development
        case "productivity", "business", "utilities", "reference", "education", "finance", "graphics-design",
             "medical":
            self = .productivity
        case "social-networking": self = .communication
        case "music", "video", "entertainment", "news", "lifestyle", "sports", "photography", "travel",
             "healthcare-fitness":
            self = .entertainment
        default:
            if appStoreCategory?.contains("games") == true {
                self = .entertainment
            } else {
                self = .other
            }
        }
    }
}

/// A stretch with one app in front.
public struct ScreenSession: Codable, Sendable, Equatable {
    public var app: String
    public var start: Date
    public var end: Date

    public init(app: String, start: Date, end: Date) {
        self.app = app
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// A stretch away from the Mac: the screen was locked or asleep.
public struct ScreenBreak: Codable, Sendable, Equatable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

/// Seconds spent in each app on one day.
public struct ScreenDay: Codable, Sendable, Equatable {
    public var day: String
    public var seconds: [String: Double] = [:]
    /// Kept for today only; older days need just their totals.
    public var sessions: [ScreenSession] = []
    public var breaks: [ScreenBreak] = []

    public init(day: String) {
        self.day = day
    }

    private enum CodingKeys: String, CodingKey {
        case day, seconds, sessions, breaks
    }

    /// Logs written by earlier versions have only `day` and `seconds`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(String.self, forKey: .day)
        seconds = try container.decodeIfPresent([String: Double].self, forKey: .seconds) ?? [:]
        sessions = (try? container.decodeIfPresent([ScreenSession].self, forKey: .sessions)) ?? []
        breaks = (try? container.decodeIfPresent([ScreenBreak].self, forKey: .breaks)) ?? []
    }

    public var total: Double {
        seconds.values.reduce(0, +)
    }
}

/// GlassWork's own record of the frontmost app. Off until the user turns it on; kept for 30 days.
public struct ScreenTimeLog: Codable, Sendable, Equatable {
    public static let key = "screen-time"
    public static let keepDays = 30

    /// A gap shorter than this does not count as a break, and a session resumes across it.
    public static let breakThreshold: TimeInterval = 300
    private static let sessionMergeGap: TimeInterval = 60
    private static let sessionLimit = 400

    public var days: [ScreenDay] = []
    public var excluded: Set<String> = []
    /// Each app's category, remembered when it comes to the front.
    public var categories: [String: AppCategory] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case days, excluded, categories
    }

    /// A log from an earlier version must still load: failing here would replace 30 days with an empty log.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([ScreenDay].self, forKey: .days) ?? []
        excluded = try container.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? []
        categories = (try? container.decodeIfPresent([String: AppCategory].self, forKey: .categories)) ?? [:]
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds time to an app on the day it ended, then drops days past the limit.
    public mutating func record(app: String, seconds: Double, at date: Date, calendar: Calendar = .current) {
        guard seconds > 0, !excluded.contains(app) else { return }
        openDay(at: date, calendar: calendar)
        days[days.count - 1].seconds[app, default: 0] += seconds
        addSession(app: app, start: date.addingTimeInterval(-seconds), end: date)
        if days.count > Self.keepDays {
            days.removeFirst(days.count - Self.keepDays)
        }
    }

    /// Remembers time away from the Mac, if it was long enough to be a rest.
    public mutating func recordBreak(from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end.timeIntervalSince(start) >= Self.breakThreshold else { return }
        openDay(at: end, calendar: calendar)
        days[days.count - 1].breaks.append(ScreenBreak(start: start, end: end))
    }

    private mutating func openDay(at date: Date, calendar: Calendar) {
        let key = Self.dayKey(date, calendar: calendar)
        guard days.last?.day != key else { return }
        if !days.isEmpty {
            days[days.count - 1].sessions = []
            days[days.count - 1].breaks = []
        }
        days.append(ScreenDay(day: key))
    }

    private mutating func addSession(app: String, start: Date, end: Date) {
        let last = days.count - 1
        if let previous = days[last].sessions.last, previous.app == app,
           start.timeIntervalSince(previous.end) < Self.sessionMergeGap
        {
            days[last].sessions[days[last].sessions.count - 1].end = end
            return
        }
        days[last].sessions.append(ScreenSession(app: app, start: start, end: end))
        if days[last].sessions.count > Self.sessionLimit {
            days[last].sessions.removeFirst()
        }
    }

    public func today(_ date: Date = Date()) -> ScreenDay? {
        let key = Self.dayKey(date)
        return days.last { $0.day == key }
    }

    /// Apps by time spent, most used first.
    public func topApps(in day: ScreenDay, limit: Int) -> [(app: String, seconds: Double)] {
        day.seconds.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
}
