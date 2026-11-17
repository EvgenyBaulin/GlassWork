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

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func aYearlyDateComesBackNextYear() {
        let birthday = ImportantDate(title: "B", date: day(2020, 3, 10), repeats: .yearly)
        let next = birthday.nextOccurrence(from: day(2026, 5, 1), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: next) == DateComponents(
            year: 2027,
            month: 3,
            day: 10
        ))
        #expect(birthday.daysLeft(from: day(2026, 3, 9), calendar: calendar) == 1)
        #expect(birthday.daysLeft(from: day(2026, 3, 10), calendar: calendar) == 0)
    }

    @Test func aMonthlyDateComesBackNextMonth() {
        let rent = ImportantDate(title: "R", date: day(2026, 1, 15), repeats: .monthly)
        #expect(rent.daysLeft(from: day(2026, 5, 10), calendar: calendar) == 5)
        #expect(rent.daysLeft(from: day(2026, 5, 20), calendar: calendar) == 26)
    }

    @Test func aDateAheadAndOneThatDoesNotRepeatStayPut() {
        let ahead = ImportantDate(title: "A", date: day(2030, 1, 1), repeats: .yearly)
        #expect(ahead.nextOccurrence(from: day(2026, 5, 1), calendar: calendar) == ahead.date)
        let past = ImportantDate(title: "P", date: day(2026, 1, 1))
        #expect(past.daysLeft(from: day(2026, 1, 11), calendar: calendar) == -10)
    }

    @Test func oldSavedDatesDecodeWithoutRepeat() throws {
        let json = #"{"id":"6C8C6C1E-0000-4000-8000-000000000001","title":"Old","date":0}"#
        let item = try JSONDecoder().decode(ImportantDate.self, from: Data(json.utf8))
        #expect(item.repeats == .none)
        let saved = try JSONEncoder().encode(ImportantDate(title: "N", date: .now, repeats: .monthly))
        #expect(try JSONDecoder().decode(ImportantDate.self, from: saved).repeats == .monthly)
    }

    @Test func movesCitiesUpAndDown() {
        var data = EverydayData()
        data.cities = [
            WorldCity(name: "A", timeZone: "Europe/Paris"),
            WorldCity(name: "B", timeZone: "Asia/Tokyo"),
            WorldCity(name: "C", timeZone: "America/New_York"),
        ]
        data.moveCity("America/New_York", by: -1)
        #expect(data.cities.map(\.name) == ["A", "C", "B"])
        data.moveCity("Europe/Paris", by: -1)
        data.moveCity("Asia/Tokyo", by: 1)
        #expect(data.cities.map(\.name) == ["A", "C", "B"])
        data.moveCity("Asia/Tokyo", by: -2)
        #expect(data.cities.map(\.name) == ["B", "A", "C"])
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

    @Test func moscowSunriseFallsInTheMorning() throws {
        // 2024-03-20: sunrise about 03:30 UTC, sunset about 15:40 UTC.
        let times = Astronomy.sunTimes(
            on: Date(timeIntervalSince1970: 1_710_936_000),
            latitude: 55.75,
            longitude: 37.62
        )
        let sunrise = try #require(times.sunrise)
        let sunset = try #require(times.sunset)
        #expect(abs(sunrise.timeIntervalSince1970 - 1_710_905_400) < 900)
        #expect(abs(sunset.timeIntervalSince1970 - 1_710_949_200) < 900)
    }

    @Test func polarNightHasNoSunrise() {
        // 2024-12-21 12:00 UTC at 80° north.
        let times = Astronomy.sunTimes(on: Date(timeIntervalSince1970: 1_734_782_400), latitude: 80, longitude: 0)
        #expect(times.sunrise == nil)
    }
}

@MainActor
struct FinishedTimerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStore() -> (EverydayStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return (EverydayStore(store: SnapshotStore(directory: folder)), folder)
    }

    @Test func finishedTimerMovesToItsOwnListAndStaysUntilDismissed() {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        var reported: [String] = []
        store.onTimerFinished = { reported.append($0.title) }
        store.update { $0.timers = [
            CountdownTimer(title: "Tea", duration: 60, start: start),
            CountdownTimer(title: "Egg", duration: 600, start: start),
        ] }
        store.tick(at: start.addingTimeInterval(90))
        #expect(store.data.timers.map(\.title) == ["Egg"])
        #expect(store.data.finishedTimers.map(\.title) == ["Tea"])
        #expect(store.data.finishedTimers.first?.finishedAt == start.addingTimeInterval(60))
        #expect(reported == ["Tea"])
        store.tick(at: start.addingTimeInterval(120))
        #expect(store.data.finishedTimers.count == 1)
        store.dismissFinishedTimer(store.data.finishedTimers[0].id)
        #expect(store.data.finishedTimers.isEmpty)
    }

    @Test func listKeepsTheNewestFirstAndIsLimited() {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        for index in 0 ..< EverydayData.finishedLimit + 2 {
            store.update { $0.timers = [CountdownTimer(title: "T\(index)", duration: 1, start: start)] }
            store.tick(at: start.addingTimeInterval(Double(index) + 5))
        }
        #expect(store.data.finishedTimers.count == EverydayData.finishedLimit)
        #expect(store.data.finishedTimers.first?.title == "T\(EverydayData.finishedLimit + 1)")
    }

    @Test func dataSavedBeforeFinishedTimersStillLoads() throws {
        var data = EverydayData()
        data.note = "hi"
        let encoded = try JSONEncoder().encode(data)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["finishedTimers"] != nil)
        object["finishedTimers"] = nil
        let loaded = try JSONDecoder().decode(EverydayData.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(loaded.finishedTimers.isEmpty)
        #expect(loaded.note == "hi")
    }
}
