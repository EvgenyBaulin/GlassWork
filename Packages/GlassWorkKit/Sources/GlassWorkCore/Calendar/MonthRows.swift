import Foundation

/// One row of a month grid: the days of a week and its ISO week number.
public struct MonthRow: Equatable, Sendable {
    public let week: Int
    /// Seven cells; nil before the 1st and after the last day.
    public let days: [Int?]
}

public enum MonthRows {
    /// Rows of the month in `calendar`'s week order. The week number is the ISO one of the row's middle day,
    /// which is the day ISO weeks are named after (the Thursday of a Monday-first row).
    public static func rows(for month: Date, calendar: Calendar = .current) -> [MonthRow] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let cells: [Int?] = Array(repeating: nil, count: leading) + (1 ... count).map(Optional.some)
        let padded = cells + Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).compactMap { start in
            let offset = start + 3 - leading
            guard let middle = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            return MonthRow(week: iso.component(.weekOfYear, from: middle), days: Array(padded[start ..< start + 7]))
        }
    }
}
