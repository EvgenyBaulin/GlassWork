import Foundation
@testable import GlassWorkCore
import Testing

struct TimerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func countsDownAndFinishes() {
        let timer = CountdownTimer(title: "Tea", duration: 60, start: start)
        #expect(timer.remaining(at: start.addingTimeInterval(20)) == 40)
        #expect(!timer.isFinished(at: start.addingTimeInterval(59)))
        #expect(timer.isFinished(at: start.addingTimeInterval(60)))
    }

    @Test func pausingKeepsWhatIsLeft() {
        var timer = CountdownTimer(title: "Tea", duration: 60, start: start)
        timer.togglePause(at: start.addingTimeInterval(10))
        #expect(timer.remaining(at: start.addingTimeInterval(500)) == 50)

        timer.togglePause(at: start.addingTimeInterval(500))
        #expect(timer.remaining(at: start.addingTimeInterval(510)) == 40)
    }

    @Test(arguments: [(90.0, "1:30"), (3723.0, "1:02:03"), (0.4, "0:01")])
    func formatsClockText(interval: Double, expected: String) {
        #expect(interval.clockText == expected)
    }
}

struct StopwatchTests {
    @Test func accumulatesAcrossPauses() {
        var watch = Stopwatch()
        let start = Date(timeIntervalSince1970: 1000)
        watch.toggle(at: start)
        watch.toggle(at: start.addingTimeInterval(5))
        watch.toggle(at: start.addingTimeInterval(100))
        #expect(watch.elapsed(at: start.addingTimeInterval(102)) == 7)
        watch.reset()
        #expect(watch.elapsed(at: start) == 0)
    }
}

struct DatesTests {
    @Test func sortsSoonestFirstAndPastLast() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var data = EverydayData()
        data.dates = [
            ImportantDate(title: "Past", date: now.addingTimeInterval(-86400 * 3)),
            ImportantDate(title: "Far", date: now.addingTimeInterval(86400 * 30)),
            ImportantDate(title: "Soon", date: now.addingTimeInterval(86400 * 2)),
        ]
        #expect(data.sortedDates(from: now).map(\.title) == ["Soon", "Far", "Past"])
    }

    @Test func keepsRecentColorsUnique() {
        var data = EverydayData()
        data.addColor("#111111")
        data.addColor("#222222")
        data.addColor("#111111")
        #expect(data.colors == ["#111111", "#222222"])
    }
}

struct AstronomyTests {
    @Test func knownFullMoonIsFull() {
        // 2024-01-25 17:54 UTC.
        let date = Date(timeIntervalSince1970: 1_706_205_240)
        #expect(Astronomy.moonPhase(at: date) == .full)
        #expect(Astronomy.moonIllumination(at: date) > 0.97)
    }

    @Test func moscowEquinoxDayIsAboutTwelveHours() throws {
        // 2024-03-20 12:00 UTC.
        let times = Astronomy.sunTimes(
            on: Date(timeIntervalSince1970: 1_710_936_000),
            latitude: 55.75,
            longitude: 37.62
        )
        let daylight = try #require(times.daylight)
        #expect(abs(daylight - 12.2 * 3600) < 900)
    }

    @Test func polarNightHasNoSunrise() {
        // 2024-12-21 12:00 UTC at 80° north.
        let times = Astronomy.sunTimes(on: Date(timeIntervalSince1970: 1_734_782_400), latitude: 80, longitude: 0)
        #expect(times.sunrise == nil)
    }
}
