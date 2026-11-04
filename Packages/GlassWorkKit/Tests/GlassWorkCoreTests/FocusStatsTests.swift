import Foundation
@testable import GlassWorkCore
import Testing

struct FocusStatsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// 2026-11-04 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_793_750_400 + 12 * 3600)

    private func log() -> ScreenTimeLog {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 3600, at: now.addingTimeInterval(-2 * 86400), calendar: calendar)
        log.record(app: "Xcode", seconds: 7200, at: now.addingTimeInterval(-86400), calendar: calendar)
        log.record(app: "Xcode", seconds: 5400, at: now, calendar: calendar)
        log.record(app: "Safari", seconds: 1800, at: now, calendar: calendar)
        return log
    }

    @Test func todayAndYesterday() {
        let stats = FocusStats(log: log(), at: now, calendar: calendar)
        #expect(stats.today == 7200)
        #expect(stats.yesterday == 7200)
        #expect(stats.hasData)
        #expect(stats.week.count == 7)
        #expect(stats.week.last?.seconds == 7200)
        #expect(stats.week.first?.seconds == 0)
    }

    @Test func topAppShare() {
        let stats = FocusStats(log: log(), at: now, calendar: calendar)
        #expect(stats.topApp?.name == "Xcode")
        #expect(stats.topApp?.share == 0.75)
    }

    @Test func averageSkipsEmptyDays() {
        let stats = FocusStats(log: log(), at: now, calendar: calendar)
        #expect(abs(stats.weekAverage - (3600 + 7200 + 7200) / 3) < 0.001)
    }

    @Test func emptyLogHasNoData() {
        let stats = FocusStats(log: ScreenTimeLog(), at: now, calendar: calendar)
        #expect(!stats.hasData)
        #expect(stats.today == 0)
        #expect(stats.topApp == nil)
        #expect(stats.weekAverage == 0)
    }
}
