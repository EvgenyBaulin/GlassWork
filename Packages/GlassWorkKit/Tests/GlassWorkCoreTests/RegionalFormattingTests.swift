import Foundation
@testable import GlassWorkCore
import Testing

struct RegionalFormattingTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")
    private var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// 14:05 UTC on Tuesday 17 November 2026.
    private let afternoon = Date(timeIntervalSince1970: 1_794_924_000 + 300)

    private func settings(_ format: TimeFormat, _ weekday: FirstWeekday = .system) -> RegionalSettings {
        var settings = RegionalSettings()
        settings.timeFormat = format
        settings.firstWeekday = weekday
        return settings
    }

    @Test func timeFollowsTheChosenClock() {
        let twelve = afternoon.timeText(using: settings(.twelveHour), base: german, timeZone: .gmt)
        #expect(twelve.contains("2:05"))
        #expect(twelve.uppercased().contains("PM"))
        #expect(afternoon.timeText(using: settings(.twentyFourHour), base: english, timeZone: .gmt) == "14:05")
    }

    @Test func systemKeepsTheMacsClock() {
        #expect(afternoon.timeText(using: settings(.system), base: english, timeZone: .gmt).hasPrefix("2:05"))
        #expect(afternoon.timeText(using: settings(.system), base: german, timeZone: .gmt) == "14:05")
    }

    @Test func systemStyleIsTheOriginalStyle() {
        let style = Date.FormatStyle(date: .omitted, time: .shortened)
        let same = style.regional(RegionalSettings(), base: .current)
        #expect(afternoon.formatted(same) == afternoon.formatted(style))
    }

    @Test func hourOnlyStylesFollowTheClock() {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).hour(.defaultDigits(amPM: .omitted))
        style.timeZone = .gmt
        #expect(afternoon.formatted(style.regional(settings(.twentyFourHour), base: english)) == "14")
        // The exact text differs between system versions ("2", "02 Uhr"); what matters is the 12-hour clock.
        let german12 = afternoon.formatted(style.regional(settings(.twelveHour), base: german))
        #expect(german12.contains("2") && !german12.contains("14"))
    }

    @Test func weekProgressStartsOnTheChosenDay() {
        let monday = settings(.system, .monday).calendar(base: gregorian)
        let sunday = settings(.system, .sunday).calendar(base: gregorian)
        let mondayWeek = PeriodProgress(.week, at: afternoon, calendar: monday)
        let sundayWeek = PeriodProgress(.week, at: afternoon, calendar: sunday)
        // Tuesday 17 November 2026: the week began on the 16th, or on Sunday the 15th.
        #expect(monday.component(.day, from: mondayWeek.start) == 16)
        #expect(sunday.component(.day, from: sundayWeek.start) == 15)
    }

    @Test func aSnapshotWithoutTheChoiceReadsAsSystem() throws {
        var snapshot = WidgetSnapshot(date: afternoon)
        #expect(snapshot.regional == nil)
        let plain = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(plain.regional == nil)
        #expect((plain.regional ?? RegionalSettings()) == RegionalSettings())
        snapshot.regional = settings(.twentyFourHour, .monday)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded.regional == settings(.twentyFourHour, .monday))
    }
}
