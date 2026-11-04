import Foundation

/// How far a day, week, month, quarter or year has gone.
public struct PeriodProgress: Sendable, Equatable {
    public enum Period: String, CaseIterable, Sendable {
        case day, week, month, quarter, year

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .quarter: .quarter
            case .year: .year
            }
        }
    }

    public let period: Period
    public let start: Date
    public let end: Date
    /// 0 at the start, 1 at the end.
    public let share: Double
    /// Whole calendar days after today before the period ends; 0 on its last day.
    public let daysLeft: Int

    public init(_ period: Period, at date: Date, calendar: Calendar = .current) {
        self.period = period
        let interval = calendar.dateInterval(of: period.component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86400)
        start = interval.start
        end = interval.end
        share = min(max(date.timeIntervalSince(interval.start) / max(interval.duration, 1), 0), 1)
        let today = calendar.startOfDay(for: date)
        let last = calendar.startOfDay(for: interval.end.addingTimeInterval(-1))
        daysLeft = calendar.dateComponents([.day], from: today, to: last).day ?? 0
    }
}

/// Time to the next weekend, or how much of the current one is gone. Which days make up the weekend
/// comes from the calendar's locale.
public struct WeekendCountdown: Sendable, Equatable {
    public let isWeekend: Bool
    /// The weekend under way, or the next one.
    public let weekend: DateInterval
    /// The weekend after `weekend`.
    public let following: DateInterval?
    /// Calendar days until the weekend starts; 0 during it.
    public let daysUntil: Int
    /// Time until the weekend starts, or until it ends while it lasts.
    public let remaining: TimeInterval
    /// Working stretch gone before the weekend, or the share of the weekend gone while it lasts.
    public let progress: Double

    public init(at date: Date, calendar: Calendar = .current) {
        // A weekend is at most a few days long, so looking back three days finds the one under way.
        let lookback = date.addingTimeInterval(-3 * 86400)
        let candidate = calendar.nextWeekend(startingAfter: lookback)
        let current = candidate.flatMap { $0.end > date ? $0 : nil }
        let next = current ?? calendar.nextWeekend(startingAfter: date)
        let weekend = next ?? DateInterval(start: date, duration: 0)
        self.weekend = weekend
        isWeekend = weekend.start <= date && date < weekend.end
        following = calendar.nextWeekend(startingAfter: weekend.start)
        if isWeekend {
            daysUntil = 0
            remaining = weekend.end.timeIntervalSince(date)
            progress = date.timeIntervalSince(weekend.start) / max(weekend.duration, 1)
        } else {
            daysUntil = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: weekend.start)
            ).day ?? 0
            remaining = weekend.start.timeIntervalSince(date)
            let previousEnd = calendar.nextWeekend(startingAfter: date, direction: .backward)?.end
                ?? weekend.start.addingTimeInterval(-5 * 86400)
            progress = min(max(
                date.timeIntervalSince(previousEnd) / max(weekend.start.timeIntervalSince(previousEnd), 1),
                0
            ), 1)
        }
    }
}

public extension TimeInterval {
    /// "0:07", "12:30" or "1:02:03", rounding down the way a stopwatch does.
    var elapsedText: String {
        let total = Int(max(self, 0))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
