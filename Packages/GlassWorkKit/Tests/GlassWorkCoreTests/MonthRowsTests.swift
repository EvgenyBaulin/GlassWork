import Foundation
@testable import GlassWorkCore
import Testing

struct MonthRowsTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar(firstWeekday: 2).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func mondayFirstWeeksFollowIso() {
        // February 2026 starts on a Sunday: weeks 5 (just the 1st), 6, 7, 8, 9.
        let rows = MonthRows.rows(for: date(2026, 2, 10), calendar: calendar(firstWeekday: 2))

        #expect(rows.map(\.week) == [5, 6, 7, 8, 9])
        #expect(rows.first?.days == [nil, nil, nil, nil, nil, nil, 1])
        #expect(rows.last?.days == [23, 24, 25, 26, 27, 28, nil])
    }

    @Test func sundayFirstRowTakesTheWeekOfItsMiddleDay() {
        // January 2026 starts on a Thursday. The Sunday-first row of Dec 28 to Jan 3 has Wednesday Dec 31,
        // which is in ISO week 1 of 2026.
        let rows = MonthRows.rows(for: date(2026, 1, 15), calendar: calendar(firstWeekday: 1))

        #expect(rows.first?.week == 1)
        #expect(rows.first?.days == [nil, nil, nil, nil, 1, 2, 3])
    }

    @Test func januaryCanStartInTheLastWeekOfTheOldYear() {
        // January 2021 starts on a Friday that belongs to ISO week 53 of 2020.
        let rows = MonthRows.rows(for: date(2021, 1, 20), calendar: calendar(firstWeekday: 2))

        #expect(rows.first?.week == 53)
        #expect(rows[1].week == 1)
    }

    @Test func decemberCanEndInWeekOneOfTheNextYear() {
        // December 2025 ends on a Wednesday that belongs to ISO week 1 of 2026.
        let rows = MonthRows.rows(for: date(2025, 12, 5), calendar: calendar(firstWeekday: 2))

        #expect(rows.last?.week == 1)
        #expect(rows.last?.days == [29, 30, 31, nil, nil, nil, nil])
    }

    @Test func everyRowHasSevenCells() {
        let rows = MonthRows.rows(for: date(2024, 2, 1), calendar: calendar(firstWeekday: 2))

        #expect(rows.allSatisfy { $0.days.count == 7 })
        #expect(rows.flatMap(\.days).compactMap(\.self).count == 29)
    }
}
