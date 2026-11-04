import Foundation

/// Seconds spent in each app on one day.
public struct ScreenDay: Codable, Sendable, Equatable {
    public var day: String
    public var seconds: [String: Double] = [:]

    public init(day: String) {
        self.day = day
    }

    public var total: Double {
        seconds.values.reduce(0, +)
    }
}

/// GlassWork's own record of the frontmost app. Off until the user turns it on; kept for 30 days.
public struct ScreenTimeLog: Codable, Sendable, Equatable {
    public static let key = "screen-time"
    public static let keepDays = 30

    public var days: [ScreenDay] = []
    public var excluded: Set<String> = []

    public init() {}

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds time to an app on the day it ended, then drops days past the limit.
    public mutating func record(app: String, seconds: Double, at date: Date, calendar: Calendar = .current) {
        guard seconds > 0, !excluded.contains(app) else { return }
        let key = Self.dayKey(date, calendar: calendar)
        if days.last?.day != key {
            days.append(ScreenDay(day: key))
        }
        days[days.count - 1].seconds[app, default: 0] += seconds
        if days.count > Self.keepDays {
            days.removeFirst(days.count - Self.keepDays)
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
