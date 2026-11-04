import Foundation
@testable import GlassWorkCore
import Testing

struct ScreenLogFormatTests {
    /// What earlier versions wrote. Failing to read it would replace 30 days with an empty log.
    @Test func readsALogWrittenByAnEarlierVersion() throws {
        let old = #"{"days":[{"day":"2026-11-03","seconds":{"Xcode":3600,"Safari":60}}],"excluded":["Secret"]}"#

        let log = try JSONDecoder().decode(ScreenTimeLog.self, from: Data(old.utf8))

        #expect(log.days.first?.total == 3660)
        #expect(log.days.first?.sessions.isEmpty == true)
        #expect(log.excluded == ["Secret"])
        #expect(log.categories.isEmpty)
    }

    @Test func aBadNewFieldDoesNotCostTheLog() throws {
        let text = #"{"days":[{"day":"2026-11-03","seconds":{"Xcode":60},"sessions":7}],"categories":"x"}"#

        let log = try JSONDecoder().decode(ScreenTimeLog.self, from: Data(text.utf8))

        #expect(log.days.first?.total == 60)
    }

    @Test func survivesARoundTrip() throws {
        var log = ScreenTimeLog()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        log.record(app: "Xcode", seconds: 60, at: date)
        log.recordBreak(from: date, to: date.addingTimeInterval(600))
        log.categories["Xcode"] = .development

        let data = try JSONEncoder().encode(log)

        #expect(try JSONDecoder().decode(ScreenTimeLog.self, from: data) == log)
    }
}

struct ScreenSessionTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func joinsStretchesOfTheSameApp() throws {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: date)
        log.record(app: "Xcode", seconds: 60, at: date.addingTimeInterval(70))

        let sessions = try #require(log.days.last?.sessions)
        #expect(sessions.count == 1)
        #expect(sessions.first?.duration == 130)
    }

    @Test func splitsSessionsAcrossALongGap() {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: date)
        log.record(app: "Xcode", seconds: 60, at: date.addingTimeInterval(600))
        #expect(log.days.last?.sessions.count == 2)
    }

    @Test func dropsSessionsOfDaysGoneBy() {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: date)
        log.record(app: "Xcode", seconds: 60, at: date.addingTimeInterval(86400 * 2))
        #expect(log.days.first?.sessions.isEmpty == true)
        #expect(log.days.first?.total == 60)
        #expect(log.days.last?.sessions.count == 1)
    }

    @Test func aShortAbsenceIsNotABreak() {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: date)
        log.recordBreak(from: date, to: date.addingTimeInterval(120))
        #expect(log.days.last?.breaks.isEmpty == true)
    }

    @Test(arguments: [
        ("public.app-category.developer-tools", AppCategory.development),
        ("public.app-category.productivity", .productivity),
        ("public.app-category.social-networking", .communication),
        ("public.app-category.music", .entertainment),
        ("public.app-category.action-games", .entertainment),
        ("public.app-category.nothing-known", .other),
    ])
    func readsTheAppStoreCategory(text: String, expected: AppCategory) {
        #expect(AppCategory(appStoreCategory: text) == expected)
    }

    @Test func anAppWithoutACategoryIsOther() {
        #expect(AppCategory(appStoreCategory: nil) == .other)
    }
}

@MainActor
struct ScreenTrackingTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> ActivityStore {
        ActivityStore(store: SnapshotStore(directory: FileManager.default.temporaryDirectory
                .appending(path: "GlassWorkActivity-\(UUID().uuidString)", directoryHint: .isDirectory)))
    }

    @Test func aLockedScreenIsNotCountedAsAppTime() {
        let store = makeStore()
        store.appBecameActive("Xcode", at: date)
        store.screenWentAway(at: date.addingTimeInterval(60))
        store.screenCameBack(at: date.addingTimeInterval(660))
        store.appBecameActive("Safari", at: date.addingTimeInterval(720))

        let day = store.screenTime.days.last
        #expect(day?.seconds["Xcode"] == 120)
        #expect(day?.breaks.count == 1)
        #expect(day?.breaks.first?.duration == 600)
    }

    @Test func aSecondAwayNoticeDoesNotMoveTheBreak() {
        let store = makeStore()
        store.appBecameActive("Xcode", at: date)
        store.screenWentAway(at: date.addingTimeInterval(60))
        store.screenWentAway(at: date.addingTimeInterval(120))
        store.screenCameBack(at: date.addingTimeInterval(660))
        #expect(store.screenTime.days.last?.breaks.first?.start == date.addingTimeInterval(60))
    }

    @Test func flushingCountsALongSessionAsItRuns() {
        let store = makeStore()
        store.appBecameActive("Xcode", at: date)
        store.flushScreenTime(at: date.addingTimeInterval(120))
        store.flushScreenTime(at: date.addingTimeInterval(180))
        #expect(store.screenTime.days.last?.seconds["Xcode"] == 180)
    }

    @Test func remembersTheCategoryOfAnApp() {
        let store = makeStore()
        store.appBecameActive("Xcode", category: .development, at: date)
        #expect(store.screenTime.categories["Xcode"] == .development)
    }
}

struct ScreenStatsTests {
    private let calendar = Calendar.current
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 15)) ?? Date()
    }

    private struct Use {
        let back: Int
        let app: String
        let seconds: Double

        init(_ back: Int, _ app: String, _ seconds: Double) {
            self.back = back
            self.app = app
            self.seconds = seconds
        }
    }

    private func log(_ days: [Use]) -> ScreenTimeLog {
        var log = ScreenTimeLog()
        for day in days.sorted(by: { $0.back > $1.back }) {
            log.record(app: day.app, seconds: day.seconds, at: now.addingTimeInterval(Double(-day.back) * 86400))
        }
        return log
    }

    @Test func weekAddsUpAndAveragesActiveDaysOnly() {
        let stats = ScreenWeekStats(log: log([Use(0, "Xcode", 100), Use(1, "Xcode", 300)]), at: now)
        #expect(stats.total == 400)
        #expect(stats.dailyAverage == 200)
        #expect(stats.days.count == 7)
        #expect(stats.today == 100)
        #expect(stats.busiest?.seconds == 300)
        #expect(stats.quietest?.seconds == 100)
    }

    @Test func weekComparesWithThePreviousSevenDays() throws {
        let stats = ScreenWeekStats(log: log([Use(0, "Xcode", 150), Use(8, "Xcode", 100)]), at: now)
        #expect(stats.previousTotal == 100)
        #expect(try #require(stats.weekChange) == 0.5)
    }

    @Test func nothingToCompareGivesNoChange() {
        let stats = ScreenWeekStats(log: log([Use(0, "Xcode", 150)]), at: now)
        #expect(stats.weekChange == nil)
        #expect(stats.todayChange == nil)
    }

    @Test func emptyLogHasNoData() {
        #expect(ScreenWeekStats(log: ScreenTimeLog(), at: now).hasData == false)
    }

    @Test func hoursSplitASessionAtTheHour() throws {
        let parts = DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 30)
        let start = try #require(calendar.date(from: parts))
        let session = ScreenSession(app: "Xcode", start: start, end: start.addingTimeInterval(3600))

        let hours = ScreenHours.today([session], minimum: 2)

        #expect(hours.map(\.seconds) == [1800, 1800])
    }

    @Test func hoursKeepAMinimumWidth() throws {
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9)))
        let session = ScreenSession(app: "Xcode", start: start, end: start.addingTimeInterval(60))
        #expect(ScreenHours.today([session], minimum: 6).count == 6)
    }

    @Test func categoriesAreLargestFirstAndUnknownAppsAreOther() {
        var day = ScreenDay(day: "2026-11-04")
        day.seconds = ["Xcode": 300, "Terminal": 100, "Slack": 400, "Odd": 200]
        let categories: [String: AppCategory] = [
            "Xcode": .development, "Terminal": .development, "Slack": .communication,
        ]

        let stats = ScreenCategoryStats(day: day, categories: categories)

        #expect(stats.total == 1000)
        #expect(stats.rows.map(\.category) == [.communication, .development, .other])
        #expect(stats.rows[1].apps == ["Xcode", "Terminal"])
        #expect(stats.rows[1].share == 0.4)
    }

    @Test func aRingFindsTheSegmentUnderAShare() {
        var day = ScreenDay(day: "2026-11-04")
        day.seconds = ["Xcode": 75, "Slack": 25]
        let rows = ScreenCategoryStats(
            day: day,
            categories: ["Xcode": .development, "Slack": .communication]
        ).rows

        #expect(ScreenCategoryStats.row(at: 0.1, in: rows)?.category == .development)
        #expect(ScreenCategoryStats.row(at: 0.8, in: rows)?.category == .communication)
        #expect(ScreenCategoryStats.row(at: 0.5, in: []) == nil)
    }

    @Test func breaksMeasureFromTheLastOne() {
        var day = ScreenDay(day: "2026-11-04")
        day.sessions = [ScreenSession(app: "Xcode", start: now.addingTimeInterval(-7200), end: now)]
        day.breaks = [ScreenBreak(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(-2880))]

        let stats = ScreenBreakStats(day: day, at: now)

        #expect(stats.sinceBreak == 2880)
        #expect(stats.share == 0.8)
        #expect(stats.isDueSoon)
        #expect(stats.untilBreak == 720)
        #expect(stats.totalBreak == 720)
        #expect(stats.longestFocus?.duration == 3600)
    }

    @Test func noSessionMeansNoBreakData() {
        #expect(ScreenBreakStats(day: nil, at: now).hasData == false)
    }

    @Test func appTimeFollowsTheMostUsedApp() {
        let log = log([Use(0, "Safari", 100), Use(0, "Xcode", 300), Use(1, "Xcode", 150)])

        let app = AppTimeStats.defaultApp(in: log, at: now)
        let stats = AppTimeStats(app: "Xcode", log: log, at: now)

        #expect(app == "Xcode")
        #expect(stats.today == 300)
        #expect(stats.weekTotal == 450)
        #expect(stats.change == 1)
    }

    @Test func appTimeFallsBackToTheWeek() {
        #expect(AppTimeStats.defaultApp(in: log([Use(2, "Xcode", 150)]), at: now) == "Xcode")
    }

    @Test func topAppsAddUpAcrossDays() {
        let log = log([Use(0, "Safari", 100), Use(1, "Safari", 100), Use(0, "Xcode", 150), Use(9, "Mail", 900)])
        let top = log.topApps(days: 7, limit: 2, at: now)
        #expect(top.map(\.app) == ["Safari", "Xcode"])
        #expect(top.first?.seconds == 200)
    }
}
