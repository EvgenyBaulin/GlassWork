import Foundation
@testable import GlassWorkCore
import Testing

/// Which day a moment belongs to when a day starts at 4, across a change of the start and of the clock.
struct ScreenTimeDayTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    private func moment(_ text: String, _ zone: String = "UTC") -> Date {
        let parts = text.split { "-: T".contains($0) }.compactMap { Int($0) }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = parts[3]
        components.minute = parts[4]
        return calendar(zone).date(from: components) ?? .distantPast
    }

    private func key(_ log: ScreenTimeLog, _ text: String, _ zone: String) -> String {
        let calendar = calendar(zone)
        return ScreenTimeLog.dayKey(
            log.dayStart(containing: moment(text, zone), calendar: calendar),
            calendar: calendar
        )
    }

    @Test func changingTheDayStartMidDayKeepsOneDayPerDate() throws {
        let calendar = calendar()
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: moment("2026-11-10 23:00"), calendar: calendar)
        log.record(app: "Xcode", seconds: 60, at: moment("2026-11-11 00:30"), calendar: calendar)
        log.dayStartHour = 4
        log.record(app: "Safari", seconds: 30, at: moment("2026-11-11 02:00"), calendar: calendar)
        #expect(log.days.map(\.day) == ["2026-11-10", "2026-11-11"])
        #expect(log.days[0].seconds["Safari"] == 30)
        let today = try #require(log.today(moment("2026-11-11 02:30"), calendar: calendar))
        #expect(today.day == "2026-11-10")
    }

    @Test func aNewDayIsInsertedInOrderAndOlderOnesLoseTheirSessions() {
        let calendar = calendar()
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: moment("2026-11-10 12:00"), calendar: calendar)
        log.record(app: "Xcode", seconds: 60, at: moment("2026-11-12 12:00"), calendar: calendar)
        log.record(app: "Mail", seconds: 60, at: moment("2026-11-11 12:00"), calendar: calendar)
        #expect(log.days.map(\.day) == ["2026-11-10", "2026-11-11", "2026-11-12"])
        #expect(log.days[0].sessions.isEmpty)
        #expect(log.days[2].sessions.count == 1)
    }

    @Test func loadingMergesDuplicateDaysAndSortsThem() throws {
        let text = """
        {"days":[{"day":"2026-11-11","seconds":{"A":10}},{"day":"2026-11-10","seconds":{"A":5,"B":1}},\
        {"day":"2026-11-11","seconds":{"A":20,"C":2}}]}
        """
        let log = try JSONDecoder().decode(ScreenTimeLog.self, from: Data(text.utf8))
        #expect(log.days.map(\.day) == ["2026-11-10", "2026-11-11"])
        #expect(log.days[1].seconds == ["A": 30, "C": 2])
    }

    @Test func theDayStartIsAWallClockHourAcrossDaylightSaving() {
        var log = ScreenTimeLog()
        log.dayStartHour = 4
        let zone = "America/New_York"
        // 2026-03-08: clocks jump from 02:00 to 03:00, so the day is 23 hours long.
        #expect(key(log, "2026-03-08 03:30", zone) == "2026-03-07")
        #expect(key(log, "2026-03-08 04:00", zone) == "2026-03-08")
        #expect(key(log, "2026-03-09 03:59", zone) == "2026-03-08")
        // 2026-11-01: clocks go back from 02:00 to 01:00, so the day is 25 hours long.
        #expect(key(log, "2026-11-01 03:30", zone) == "2026-10-31")
        #expect(key(log, "2026-11-01 04:00", zone) == "2026-11-01")
        #expect(key(log, "2026-11-02 03:59", zone) == "2026-11-01")
        let midnight = moment("2026-11-01 00:00", zone)
        #expect(log.dayStart(containing: moment("2026-11-02 03:59", zone), calendar: calendar(zone)) == midnight)
    }

    @MainActor
    @Test func resettingWhileLockedRecordsNoBreakFromBeforeTheReset() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let folder = FileManager.default.temporaryDirectory.appending(path: "gw-\(UUID().uuidString)")
        let activity = ActivityStore(store: SnapshotStore(directory: folder), locateGH: { nil })
        var resets = 0
        activity.onScreenTimeReset = { resets += 1 }
        activity.appBecameActive("Xcode", at: start)
        activity.screenWentAway(at: start.addingTimeInterval(600))
        activity.resetScreenTime(at: start.addingTimeInterval(1200))
        #expect(resets == 1)
        activity.screenCameBack(at: start.addingTimeInterval(2400))
        let breaks = activity.screenTime.days.flatMap(\.breaks)
        #expect(breaks.count == 1)
        #expect(breaks.first?.start == start.addingTimeInterval(1200))
        // The locked time after the reset was not counted as use.
        #expect(activity.screenTime.days.flatMap { Array($0.seconds.keys) }.isEmpty)
        try? FileManager.default.removeItem(at: folder)
    }

    @Test func theHeartbeatNeverRunsFasterThanTheShortestChoice() {
        var settings = WidgetSettings()
        for bad in [0, -5, 1, 59] {
            settings.refreshSeconds = bad
            #expect(settings.heartbeatSeconds == 60)
        }
        settings.refreshSeconds = 900
        #expect(settings.heartbeatSeconds == 900)
    }
}
