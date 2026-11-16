import Foundation
@testable import GlassWorkCore
import Testing

struct DockPresetScheduleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    /// Monday 2026-11-16 at the given time, UTC.
    private func monday(_ hour: Int, _ minute: Int = 0) -> Date {
        Date(timeIntervalSince1970: 1_794_787_200 + Double(hour * 3600 + minute * 60))
    }

    private let work = DockPresetRule(presetID: "developer", weekdays: [2, 3, 4, 5, 6], minute: 9 * 60)
    private let evening = DockPresetRule(presetID: "everyday", weekdays: Set(1 ... 7), minute: 19 * 60)

    @Test func theLatestStartedRuleHolds() {
        let rules = [work, evening]
        #expect(DockPresetSchedule.current(at: monday(10), rules: rules, calendar: calendar)?.rule == work)
        #expect(DockPresetSchedule.current(at: monday(20), rules: rules, calendar: calendar)?.rule == evening)
    }

    @Test func lastNightsRuleHoldsUntilTodaysFirst() throws {
        let current = try #require(DockPresetSchedule.current(
            at: monday(7),
            rules: [work, evening],
            calendar: calendar
        ))
        #expect(current.rule == evening)
        #expect(current.start == monday(19).addingTimeInterval(-86400))
    }

    @Test func aRuleStartsOnItsMinute() {
        #expect(DockPresetSchedule.current(at: monday(9), rules: [work], calendar: calendar)?.start == monday(9))
        // A minute before, Friday's start still holds.
        let friday = monday(9).addingTimeInterval(-3 * 86400)
        #expect(DockPresetSchedule.current(at: monday(8, 59), rules: [work], calendar: calendar)?.start == friday)
    }

    @Test func otherDaysAreSkipped() {
        let weekend = DockPresetRule(presetID: "student", weekdays: [1, 7], minute: 10 * 60)
        // On Monday morning the last weekend rule started on Sunday.
        let current = DockPresetSchedule.current(at: monday(11), rules: [weekend], calendar: calendar)
        #expect(current?.start == monday(10).addingTimeInterval(-86400))
    }

    @Test func noRulesNoPreset() {
        #expect(DockPresetSchedule.current(at: monday(12), rules: [], calendar: calendar) == nil)
    }

    @Test func turningOffKeepsAppsAndDropsWidgets() {
        var dock = DockSettings()
        let app = DockApp(path: "/Applications/Notes.app", name: "Notes")
        dock.items = [.app(app)]
        let preset = DockPreset(id: "mine", name: "Mine", widgets: [.cpu, .memory])
        DockPresets.apply(preset, current: nil, to: &dock)
        #expect(dock.activePreset == "mine")

        DockPresets.turnOff(current: preset, in: &dock)

        #expect(dock.activePreset == nil)
        #expect(dock.items == [.app(app)])
    }

    @Test func scheduleSurvivesARoundTrip() throws {
        var dock = DockSettings()
        dock.followsSchedule = true
        dock.schedule = [work]
        let decoded = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(dock))
        #expect(decoded.followsSchedule)
        #expect(decoded.schedule == [work])
    }
}
