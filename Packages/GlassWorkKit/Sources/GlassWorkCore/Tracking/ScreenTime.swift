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
    /// The hour a day starts, 0 to 6: time before it belongs to the day before.
    public var dayStartHour = 0
    /// Each app's category, remembered when it comes to the front.
    public var categories: [String: AppCategory] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case days, excluded, categories, dayStartHour
    }

    /// A log from an earlier version must still load: failing here would replace 30 days with an empty log.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        days = try container.decodeIfPresent([ScreenDay].self, forKey: .days) ?? []
        excluded = try container.decodeIfPresent(Set<String>.self, forKey: .excluded) ?? []
        categories = (try? container.decodeIfPresent([String: AppCategory].self, forKey: .categories)) ?? [:]
        dayStartHour = min(max((try? container.decodeIfPresent(Int.self, forKey: .dayStartHour)) ?? 0, 0), 6)
        normalizeDays()
    }

    /// Puts the days in date order and merges two entries with the same key. A day start changed in the middle of a
    /// day used to leave such a pair behind in files written earlier.
    mutating func normalizeDays() {
        guard days.count > 1 else { return }
        var merged: [ScreenDay] = []
        for day in days.sorted(by: { $0.day < $1.day }) {
            guard let last = merged.last, last.day == day.day else {
                merged.append(day)
                continue
            }
            var combined = last
            for (app, seconds) in day.seconds {
                combined.seconds[app, default: 0] += seconds
            }
            combined.sessions = (last.sessions + day.sessions).sorted { $0.start < $1.start }
            combined.breaks = (last.breaks + day.breaks).sorted { $0.start < $1.start }
            merged[merged.count - 1] = combined
        }
        days = merged
    }

    /// Midnight of the day a moment belongs to. With a day that starts at 4, half past one in the night is still
    /// the day before.
    ///
    /// The boundary is the wall-clock hour on the calendar day, so a day of 23 or 25 hours still starts at 4.
    public func dayStart(containing date: Date, calendar: Calendar = .current) -> Date {
        let midnight = calendar.startOfDay(for: date)
        guard dayStartHour > 0,
              let boundary = calendar.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: midnight),
              date < boundary,
              let before = calendar.date(byAdding: .day, value: -1, to: midnight)
        else { return midnight }
        return calendar.startOfDay(for: before)
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds time to an app on the day it ended, then drops days past the limit.
    public mutating func record(app: String, seconds: Double, at date: Date, calendar: Calendar = .current) {
        guard seconds > 0, !excluded.contains(app) else { return }
        let index = openDay(at: date, calendar: calendar)
        days[index].seconds[app, default: 0] += seconds
        addSession(app: app, start: date.addingTimeInterval(-seconds), end: date, in: index)
        if days.count > Self.keepDays {
            days.removeFirst(days.count - Self.keepDays)
        }
    }

    /// Remembers time away from the Mac, if it was long enough to be a rest.
    public mutating func recordBreak(from start: Date, to end: Date, calendar: Calendar = .current) {
        guard end.timeIntervalSince(start) >= Self.breakThreshold else { return }
        let index = openDay(at: end, calendar: calendar)
        days[index].breaks.append(ScreenBreak(start: start, end: end))
    }

    /// The index of the day a moment belongs to. An existing day is reused, even when it is not the last: the day
    /// start can change in the middle of a day, and the moment then falls on the day before.
    private mutating func openDay(at date: Date, calendar: Calendar) -> Int {
        let key = Self.dayKey(dayStart(containing: date, calendar: calendar), calendar: calendar)
        normalizeDays()
        if let index = days.firstIndex(where: { $0.day == key }) {
            return index
        }
        let index = days.firstIndex { $0.day > key } ?? days.count
        days.insert(ScreenDay(day: key), at: index)
        // Only the newest day keeps its sessions and breaks.
        if index == days.count - 1 {
            for older in days.indices.dropLast() {
                days[older].sessions = []
                days[older].breaks = []
            }
        }
        return index
    }

    private mutating func addSession(app: String, start: Date, end: Date, in last: Int) {
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

    public func today(_ date: Date = Date(), calendar: Calendar = .current) -> ScreenDay? {
        let key = Self.dayKey(dayStart(containing: date, calendar: calendar), calendar: calendar)
        return days.last { $0.day == key }
    }

    /// Apps by time spent, most used first.
    public func topApps(in day: ScreenDay, limit: Int) -> [(app: String, seconds: Double)] {
        day.seconds.sorted { $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }
}
