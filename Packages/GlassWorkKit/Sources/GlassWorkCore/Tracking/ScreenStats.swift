import Foundation

/// What the Screen Time widgets say about the last week. Pure, so the same log always reads the same.
public struct ScreenWeekStats: Sendable, Equatable {
    public struct Day: Sendable, Equatable {
        public let date: Date
        public let seconds: Double
    }

    /// The last seven days, oldest first, ending today.
    public let days: [Day]
    /// The seven days before those.
    public let previous: [Day]

    public init(log: ScreenTimeLog, at date: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: date)
        let totals = Dictionary(log.days.map { ($0.day, $0.total) }) { first, _ in first }
        func day(_ back: Int) -> Day {
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return Day(date: day, seconds: totals[ScreenTimeLog.dayKey(day, calendar: calendar)] ?? 0)
        }
        days = (0 ..< 7).reversed().map(day)
        previous = (7 ..< 14).reversed().map(day)
    }

    public var total: Double {
        days.map(\.seconds).reduce(0, +)
    }

    public var previousTotal: Double {
        previous.map(\.seconds).reduce(0, +)
    }

    public var today: Double {
        days.last?.seconds ?? 0
    }

    public var hasData: Bool {
        total > 0
    }

    private var activeDays: [Day] {
        days.filter { $0.seconds > 0 }
    }

    /// Over days with any time, so a new install is not averaged against empty days.
    public var dailyAverage: Double {
        activeDays.isEmpty ? 0 : total / Double(activeDays.count)
    }

    public var busiest: Day? {
        activeDays.max { $0.seconds < $1.seconds }
    }

    public var quietest: Day? {
        activeDays.min { $0.seconds < $1.seconds }
    }

    /// Change against the previous seven days, nil when those have nothing to compare with.
    public var weekChange: Double? {
        previousTotal > 0 ? (total - previousTotal) / previousTotal : nil
    }

    /// Change of today against the average of the days before it.
    public var todayChange: Double? {
        let earlier = days.dropLast().map(\.seconds).filter { $0 > 0 }
        guard !earlier.isEmpty else { return nil }
        let average = earlier.reduce(0, +) / Double(earlier.count)
        return (today - average) / average
    }

    public func average(weekend: Bool, calendar: Calendar = .current) -> Double {
        let matching = activeDays.filter { calendar.isDateInWeekend($0.date) == weekend }
        return matching.isEmpty ? 0 : matching.map(\.seconds).reduce(0, +) / Double(matching.count)
    }
}

/// Today's sessions added up by hour.
public enum ScreenHours {
    /// Seconds in each hour between the first and the last hour with any time, at least `minimum` hours.
    public static func today(
        _ sessions: [ScreenSession],
        minimum: Int = 6,
        calendar: Calendar = .current
    ) -> [(hour: Date, seconds: Double)] {
        var totals: [Date: Double] = [:]
        for session in sessions {
            var start = session.start
            while start < session.end {
                let hour = calendar.dateInterval(of: .hour, for: start)
                guard let hour else { break }
                let end = min(session.end, hour.end)
                totals[hour.start, default: 0] += end.timeIntervalSince(start)
                start = end
            }
        }
        guard let first = totals.keys.min(), let last = totals.keys.max() else { return [] }
        var hours: [(hour: Date, seconds: Double)] = []
        var hour = first
        while hour <= last || hours.count < minimum {
            hours.append((hour, totals[hour] ?? 0))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
            hour = next
        }
        return hours
    }
}

/// How the day splits into categories.
public struct ScreenCategoryStats: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public let category: AppCategory
        public let seconds: Double
        public let share: Double
        /// Most used first.
        public let apps: [String]

        public var id: AppCategory {
            category
        }
    }

    /// Largest first, without empty categories.
    public let rows: [Row]
    public let total: Double

    public init(day: ScreenDay?, categories: [String: AppCategory]) {
        var seconds: [AppCategory: Double] = [:]
        var apps: [AppCategory: [(String, Double)]] = [:]
        for (app, time) in day?.seconds ?? [:] {
            let category = categories[app] ?? .other
            seconds[category, default: 0] += time
            apps[category, default: []].append((app, time))
        }
        let total = seconds.values.reduce(0, +)
        self.total = total
        rows = seconds.filter { $0.value > 0 }
            .map { category, time in
                Row(
                    category: category,
                    seconds: time,
                    share: total > 0 ? time / total : 0,
                    apps: (apps[category] ?? [])
                        .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
                        .map(\.0)
                )
            }
            .sorted { ($0.seconds, $1.category.rawValue) > ($1.seconds, $0.category.rawValue) }
    }
}

public extension ScreenCategoryStats {
    /// The row at a share of the way around a ring, from 0 to 1.
    static func row(at share: Double, in rows: [Row]) -> Row? {
        var reached = 0.0
        return rows.first { row in
            reached += row.share
            return share <= reached
        }
    }
}

/// Time at the Mac between breaks.
public struct ScreenBreakStats: Sendable, Equatable {
    /// How often the widget suggests a break.
    public static let reminderInterval: TimeInterval = 3600

    public struct Focus: Sendable, Equatable {
        public let start: Date
        public let end: Date

        public var duration: TimeInterval {
            end.timeIntervalSince(start)
        }
    }

    public let breaks: [ScreenBreak]
    /// Seconds since the last break ended, or since the day's first session.
    public let sinceBreak: TimeInterval
    public let longestFocus: Focus?
    public let averageFocus: TimeInterval
    public let hasData: Bool

    public init(day: ScreenDay?, at date: Date) {
        let breaks = day?.breaks ?? []
        self.breaks = breaks
        let first = day?.sessions.first?.start
        hasData = first != nil
        sinceBreak = max(date.timeIntervalSince(breaks.last?.end ?? first ?? date), 0)
        var focus: [Focus] = []
        var start = first
        for item in breaks {
            if let begin = start, item.start > begin {
                focus.append(Focus(start: begin, end: item.start))
            }
            start = item.end
        }
        if let begin = start, date > begin {
            focus.append(Focus(start: begin, end: date))
        }
        longestFocus = focus.max { $0.duration < $1.duration }
        averageFocus = focus.isEmpty ? 0 : focus.map(\.duration).reduce(0, +) / Double(focus.count)
    }

    public var totalBreak: TimeInterval {
        breaks.map(\.duration).reduce(0, +)
    }

    /// Share of the reminder interval used up.
    public var share: Double {
        min(sinceBreak / Self.reminderInterval, 1)
    }

    /// Seconds until a break is due. Zero or less means now.
    public var untilBreak: TimeInterval {
        Self.reminderInterval - sinceBreak
    }

    /// The ring turns orange for the last fifth of the interval.
    public var isDueSoon: Bool {
        share >= 0.8
    }
}

/// One app across today and the week.
public struct AppTimeStats: Sendable, Equatable {
    public let app: String
    public let today: Double
    /// Today's sessions of this app, latest first.
    public let sessions: [ScreenSession]
    /// Seconds per day for the last seven days, oldest first, ending today.
    public let week: [ScreenWeekStats.Day]

    /// The most used app today, or over the week when nothing has run yet today.
    public static func defaultApp(in log: ScreenTimeLog, at date: Date) -> String? {
        if let day = log.today(date), let top = log.topApps(in: day, limit: 1).first {
            return top.app
        }
        return log.topApps(days: 7, limit: 1, at: date).first?.app
    }

    public init(app: String, log: ScreenTimeLog, at date: Date, calendar: Calendar = .current) {
        self.app = app
        let today = calendar.startOfDay(for: date)
        let byDay = Dictionary(log.days.map { ($0.day, $0) }) { first, _ in first }
        week = (0 ..< 7).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let entry = byDay[ScreenTimeLog.dayKey(day, calendar: calendar)]
            return ScreenWeekStats.Day(date: day, seconds: entry?.seconds[app] ?? 0)
        }
        self.today = week.last?.seconds ?? 0
        sessions = (log.today(date)?.sessions ?? []).filter { $0.app == app }.reversed()
    }

    public var weekTotal: Double {
        week.map(\.seconds).reduce(0, +)
    }

    public var dailyAverage: Double {
        let active = week.filter { $0.seconds > 0 }
        return active.isEmpty ? 0 : weekTotal / Double(active.count)
    }

    public var busiest: ScreenWeekStats.Day? {
        week.filter { $0.seconds > 0 }.max { $0.seconds < $1.seconds }
    }

    /// Change of today against the days before it, nil with nothing to compare.
    public var change: Double? {
        let earlier = week.dropLast().map(\.seconds).filter { $0 > 0 }
        guard !earlier.isEmpty else { return nil }
        let average = earlier.reduce(0, +) / Double(earlier.count)
        return (today - average) / average
    }
}

public extension ScreenTimeLog {
    /// Apps by time over the last `days` days, most used first.
    func topApps(
        days count: Int,
        limit: Int,
        at date: Date,
        calendar: Calendar = .current
    ) -> [(app: String, seconds: Double)] {
        let today = calendar.startOfDay(for: date)
        let keys = Set((0 ..< count).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { Self.dayKey($0, calendar: calendar) }
        })
        var totals: [String: Double] = [:]
        for day in days where keys.contains(day.day) {
            totals.merge(day.seconds, uniquingKeysWith: +)
        }
        return totals
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .prefix(limit)
            .map { ($0.key, $0.value) }
    }
}
