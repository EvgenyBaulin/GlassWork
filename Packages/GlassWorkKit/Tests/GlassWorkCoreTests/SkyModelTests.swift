import Foundation
@testable import GlassWorkCore
import Testing

struct SkyModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .gmt
        return calendar
    }

    /// 2026-11-04 at the given UTC hour.
    private func utc(_ hour: Double) -> Date {
        Date(timeIntervalSince1970: 1_793_750_400 + hour * 3600)
    }

    @Test func midday() {
        let sky = SkyState(date: utc(9), latitude: 55.75, longitude: 37.62, calendar: calendar)
        #expect(sky.phase == .day)
        let progress = sky.dayProgress ?? -1
        #expect(progress > 0.3 && progress < 0.7)
        #expect(sky.next?.isSunrise == false)
        let daylight = sky.sun.daylight ?? 0
        #expect(daylight > 8 * 3600 && daylight < 10 * 3600)
    }

    @Test func nightPointsAtTomorrowsSunrise() {
        let date = utc(21.5)
        let sky = SkyState(date: date, latitude: 55.75, longitude: 37.62, calendar: calendar)
        #expect(sky.phase == .night)
        #expect(sky.dayProgress == nil)
        let night = sky.nightProgress ?? -1
        #expect(night > 0.3 && night < 0.9)
        #expect(sky.next?.isSunrise == true)
        #expect((sky.next?.date ?? .distantPast) > date)
        #expect((sky.next?.date ?? .distantFuture).timeIntervalSince(date) < 14 * 3600)
    }

    @Test func dawnIsBrightEnoughToTell() throws {
        let probe = SkyState(date: utc(9), latitude: 55.75, longitude: 37.62, calendar: calendar)
        let sunrise = try #require(probe.sun.sunrise)
        let sky = SkyState(date: sunrise.addingTimeInterval(600), latitude: 55.75, longitude: 37.62, calendar: calendar)
        #expect(sky.phase == .dawn)
    }

    @Test func polarSummerNeverSets() {
        let june = Date(timeIntervalSince1970: 1_781_000_000)
        let sky = SkyState(date: june, latitude: 78.2, longitude: 15.6, calendar: calendar)
        #expect(sky.sun.sunrise == nil)
        #expect(sky.phase == .day)
    }

    @Test func daylightSeries() {
        let series = Astronomy.daylight(
            from: utc(0),
            days: 366,
            step: 30,
            latitude: 55.75,
            longitude: 37.62,
            calendar: calendar
        )
        #expect(series.count == 13)
        let longest = series.map(\.seconds).max() ?? 0
        let shortest = series.map(\.seconds).min() ?? 0
        #expect(longest > 16 * 3600)
        #expect(shortest < 8 * 3600)
    }
}
