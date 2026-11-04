import Foundation
@testable import GlassWorkCore
import Testing

struct ClockTimeTests {
    /// 2026-11-04 21:30:15 UTC.
    private let date = Date(timeIntervalSince1970: 1_793_827_815)
    private let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    @Test func readsTheZone() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let time = ClockTime(date: date, timeZone: tokyo, reference: utc)
        #expect(time.hour == 6)
        #expect(time.minute == 30)
        #expect(time.second == 15)
        #expect(time.dayOffset == 1)
        #expect(time.hoursFromReference == 9)
    }

    @Test func previousDay() throws {
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let time = ClockTime(date: date, timeZone: losAngeles, reference: TimeZone(secondsFromGMT: 3 * 3600) ?? .gmt)
        #expect(time.dayOffset == -1)
        #expect(time.hour == 13)
    }

    @Test func handAngles() {
        let time = ClockTime(date: date, timeZone: utc, reference: utc)
        #expect(time.hourAngle == 9 * 30 + 15)
        #expect(time.minuteAngle == 30 * 6 + 1.5)
        #expect(time.secondAngle == 90)
        #expect(!time.isDaytime)
        #expect(time.dayOffset == 0)
    }

    @Test func dayShareAtMidnightAndNoon() {
        let midnight = ClockTime(date: Date(timeIntervalSince1970: 1_793_750_400), timeZone: utc, reference: utc)
        #expect(midnight.dayShare == 0)
        let noon = ClockTime(date: Date(timeIntervalSince1970: 1_793_793_600), timeZone: utc, reference: utc)
        #expect(noon.dayShare == 0.5)
    }
}
