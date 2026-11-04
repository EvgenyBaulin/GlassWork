import Foundation
@testable import GlassWorkCore
import Testing

struct PeriodProgressTests {
    /// Pinned so the results do not depend on the machine running the tests.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    @Test func halfOfADay() {
        let progress = PeriodProgress(.day, at: date(2026, 11, 4, 12), calendar: calendar)
        #expect(progress.share == 0.5)
        #expect(progress.daysLeft == 0)
    }

    @Test func weekStartsOnTheCalendarsFirstDay() {
        // Wednesday noon is 2.5 days into a week that starts on Monday.
        let progress = PeriodProgress(.week, at: date(2026, 11, 4, 12), calendar: calendar)
        #expect(abs(progress.share - 2.5 / 7) < 0.000_1)
        #expect(progress.daysLeft == 4)
    }

    @Test func monthAndYear() {
        let month = PeriodProgress(.month, at: date(2026, 11, 16), calendar: calendar)
        #expect(month.daysLeft == 14)
        #expect(abs(month.share - 15 / 30) < 0.000_1)
        let year = PeriodProgress(.year, at: date(2026, 12, 31, 12), calendar: calendar)
        #expect(year.daysLeft == 0)
        #expect(year.share > 0.99)
        let quarter = PeriodProgress(.quarter, at: date(2026, 11, 4), calendar: calendar)
        #expect(quarter.start == date(2026, 10, 1))
        #expect(quarter.end == date(2027, 1, 1))
    }

    @Test func countsDownToTheWeekend() {
        // Wednesday: Saturday is three calendar days away.
        let weekend = WeekendCountdown(at: date(2026, 11, 4, 12), calendar: calendar)
        #expect(!weekend.isWeekend)
        #expect(weekend.weekend.start == date(2026, 11, 7))
        #expect(weekend.daysUntil == 3)
        #expect(weekend.remaining == 2.5 * 86400)
        #expect(weekend.following?.start == date(2026, 11, 14))
        #expect(weekend.progress > 0.4 && weekend.progress < 0.7)
    }

    @Test func duringTheWeekend() {
        // Sunday noon: the weekend is three quarters over.
        let weekend = WeekendCountdown(at: date(2026, 11, 8, 12), calendar: calendar)
        #expect(weekend.isWeekend)
        #expect(weekend.daysUntil == 0)
        #expect(weekend.remaining == 12 * 3600)
        #expect(weekend.progress == 0.75)
        #expect(weekend.following?.start == date(2026, 11, 14))
    }

    @Test func mondayMorningIsWorkAgain() {
        let weekend = WeekendCountdown(at: date(2026, 11, 9, 1), calendar: calendar)
        #expect(!weekend.isWeekend)
        #expect(weekend.weekend.start == date(2026, 11, 14))
        #expect(weekend.daysUntil == 5)
        #expect(weekend.progress < 0.05)
    }

    @Test func elapsedTextRoundsDown() {
        #expect(TimeInterval(0).elapsedText == "0:00")
        #expect(TimeInterval(59.9).elapsedText == "0:59")
        #expect(TimeInterval(3723).elapsedText == "1:02:03")
        #expect(TimeInterval(-5).elapsedText == "0:00")
    }
}
