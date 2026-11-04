import Foundation

/// Active time from the Screen Time log, the way the Focus Time widget tells it.
public struct FocusStats: Sendable, Equatable {
    /// Active seconds today.
    public let today: Double
    public let yesterday: Double
    /// Active seconds for each of the last seven days, oldest first, ending today.
    public let week: [(date: Date, seconds: Double)]
    /// The app that held the most time today, and its share of the day's total.
    public let topApp: (name: String, share: Double)?
    public let hasData: Bool

    public init(log: ScreenTimeLog, at date: Date, calendar: Calendar = .current) {
        hasData = !log.days.isEmpty
        let today = calendar.startOfDay(for: date)
        let totals = Dictionary(log.days.map { ($0.day, $0) }) { first, _ in first }
        func day(_ back: Int) -> (Date, ScreenDay?) {
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            return (day, totals[ScreenTimeLog.dayKey(day, calendar: calendar)])
        }
        self.today = day(0).1?.total ?? 0
        yesterday = day(1).1?.total ?? 0
        week = (0 ..< 7).reversed().map { back in
            let (date, entry) = day(back)
            return (date, entry?.total ?? 0)
        }
        if let entry = day(0).1, let top = log.topApps(in: entry, limit: 1).first, entry.total > 0 {
            topApp = (top.app, top.seconds / entry.total)
        } else {
            topApp = nil
        }
    }

    /// Average active seconds over the days of the last week that have any time.
    public var weekAverage: Double {
        let active = week.map(\.seconds).filter { $0 > 0 }
        return active.isEmpty ? 0 : active.reduce(0, +) / Double(active.count)
    }

    public static func == (lhs: FocusStats, rhs: FocusStats) -> Bool {
        lhs.today == rhs.today && lhs.yesterday == rhs.yesterday && lhs.hasData == rhs.hasData
            && lhs.week.map(\.seconds) == rhs.week.map(\.seconds) && lhs.topApp?.name == rhs.topApp?.name
    }
}
