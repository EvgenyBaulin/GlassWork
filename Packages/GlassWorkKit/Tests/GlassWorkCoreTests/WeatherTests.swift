import Foundation
@testable import GlassWorkCore
import Testing

private let moscow = WeatherPlace(id: 524_901, name: "Moscow", country: "Russia", latitude: 55.75, longitude: 37.62)
/// 09:30 in Moscow on the day the forecast fixture starts.
private let morning = Date(timeIntervalSince1970: 1_793_773_800)

struct OpenMeteoParserTests {
    private func report() throws -> WeatherReport {
        try OpenMeteo.report(from: fixture("open-meteo-forecast-handmade.json"), place: moscow, now: morning)
    }

    @Test func readsCurrentConditions() throws {
        let report = try report()

        #expect(report.timeZone == "Europe/Moscow")
        #expect(report.current.temperature == 7.4)
        #expect(report.current.feelsLike == 4.9)
        #expect(report.current.humidity == 71)
        #expect(report.current.windSpeed == 4.1)
        #expect(report.current.condition == .partlyCloudy)
        #expect(report.current.isDay)
    }

    @Test func hoursStartWithTheOneUnderWay() throws {
        let first = try #require(report().hours.first)

        // 09:00 Moscow is 06:00 UTC: the wall-clock text is read with the response's own offset.
        #expect(first.date == morning.addingTimeInterval(-1800))
        #expect(try report().hours.count == 24)
    }

    @Test func aMissingValueSkipsOnlyThatHour() throws {
        let noon = morning.addingTimeInterval(9000)

        #expect(try !report().hours.contains { $0.date == noon })
        #expect(try report().hours.contains { $0.date == noon.addingTimeInterval(3600) })
    }

    @Test func readsSevenDaysAndTheirCommonRange() throws {
        let report = try report()

        #expect(report.days.count == 7)
        #expect(report.days[1].condition == .rain)
        #expect(report.temperatureRange == 0.8 ... 11.0)
    }

    @Test func readsGeocodingResults() throws {
        let places = try OpenMeteo.places(from: fixture("open-meteo-geocoding.json"))

        #expect(places.first?.id == 2_267_057)
        #expect(places.first?.name == "Лиссабон")
        #expect(places.first?.country == "Португалия")
        #expect(places.first?.latitude == 38.72509)
    }

    @Test func noMatchesHasNoResultsKey() throws {
        #expect(try OpenMeteo.places(from: fixture("open-meteo-geocoding-empty.json")).isEmpty)
    }

    @Test func aBrokenResponseThrows() {
        #expect(throws: (any Error).self) {
            try OpenMeteo.report(from: Data("{}".utf8), place: moscow, now: morning)
        }
    }

    @Test func requestAsksForMetresPerSecondAndTheLocalZone() throws {
        let query = try #require(OpenMeteo.forecastURL(for: moscow)?.query())

        #expect(query.contains("wind_speed_unit=ms"))
        #expect(query.contains("timezone=auto"))
        #expect(query.contains("forecast_days=7"))
    }
}

struct WeatherConditionTests {
    @Test(arguments: [
        (0, WeatherCondition.clear), (2, .partlyCloudy), (3, .cloudy), (45, .fog), (53, .drizzle), (63, .rain),
        (67, .freezingRain), (75, .snow), (81, .showers), (86, .snowShowers), (99, .thunderstorm), (42, .unknown),
    ])
    func groupsWMOCodes(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test func nightHasItsOwnSymbols() {
        #expect(WeatherCondition.clear.symbol(isDay: true) == "sun.max")
        #expect(WeatherCondition.clear.symbol(isDay: false) == "moon.stars")
    }

    @Test(arguments: [(0.9, UVLevel.low), (3.0, .moderate), (7.4, .high), (10.0, .veryHigh), (11.2, .extreme)])
    func namesUVLevels(index: Double, expected: UVLevel) {
        #expect(UVLevel(index: index) == expected)
    }
}

struct RefreshScheduleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func asksRightAwayTheFirstTime() {
        #expect(RefreshSchedule().isDue(at: start))
    }

    @Test func waitsThirtyMinutesAfterSuccess() {
        var schedule = RefreshSchedule()
        schedule.record(success: true, at: start)

        #expect(!schedule.isDue(at: start.addingTimeInterval(29 * 60)))
        #expect(schedule.isDue(at: start.addingTimeInterval(30 * 60)))
    }

    @Test func retriesFiveMinutesAfterFailure() {
        var schedule = RefreshSchedule()
        schedule.record(success: false, at: start)

        #expect(!schedule.isDue(at: start.addingTimeInterval(4 * 60)))
        #expect(schedule.isDue(at: start.addingTimeInterval(5 * 60)))
    }

    @Test func freshDataFromThePreviousLaunchIsNotAskedForAgain() {
        let schedule = RefreshSchedule(lastSuccess: start)

        #expect(!schedule.isDue(at: start.addingTimeInterval(60)))
    }
}

@MainActor
struct WeatherStoreTests {
    private func store(_ fetcher: FakeFetcher, folder: URL = temporaryFolder()) -> WeatherStore {
        let store = WeatherStore(fetcher: fetcher, store: SnapshotStore(directory: folder))
        var settings = WeatherSettings()
        settings.places = [moscow]
        store.apply(settings)
        return store
    }

    private func forecast() -> FakeFetcher {
        FakeFetcher { _ in try fixture("open-meteo-forecast-handmade.json") }
    }

    @Test func aNewStoreHasNoPlacesAndAsksNothing() async {
        let fetcher = forecast()
        let store = WeatherStore(fetcher: fetcher, store: SnapshotStore(directory: temporaryFolder()))
        store.isActive = true

        store.tick(at: morning)
        await Task.yield()

        #expect(store.places.isEmpty)
        #expect(fetcher.requests.isEmpty)
    }

    @Test func inactiveStoreStaysOffTheNetwork() async {
        let fetcher = forecast()
        let store = store(fetcher)

        store.tick(at: morning)
        await Task.yield()

        #expect(fetcher.requests.isEmpty)
    }

    @Test func theMacsPositionIsIgnoredUntilTurnedOn() {
        let store = store(forecast())
        let here = WeatherPlace(id: WeatherPlace.currentLocationID, name: "", country: "", latitude: 1, longitude: 2)

        store.setCurrentPlace(here)
        #expect(store.places == [moscow])

        var settings = store.settings
        settings.useCurrentLocation = true
        store.apply(settings)
        #expect(store.places == [here, moscow])
    }

    @Test func goingOfflineKeepsTheLastReport() async {
        let isOnline = Flag(true)
        let fetcher = FakeFetcher { _ in
            guard isOnline.value else { throw URLError(.notConnectedToInternet) }
            return try fixture("open-meteo-forecast-handmade.json")
        }
        let store = store(fetcher)

        await store.refresh(at: morning)
        #expect(store.status == .ready)
        #expect(!store.isStale)

        isOnline.value = false
        await store.refresh(at: morning.addingTimeInterval(1800))

        #expect(store.status == .offline)
        #expect(store.isStale)
        #expect(store.primaryReport?.fetchedAt == morning)
    }

    @Test func aServerErrorIsNotCalledOffline() async {
        let store = store(FakeFetcher { _ in throw HTTPError.status(500) })

        await store.refresh(at: morning)

        #expect(store.status == .failed)
    }

    @Test func theLastDataSurvivesARelaunch() async {
        let folder = temporaryFolder()
        await store(forecast(), folder: folder).refresh(at: morning)

        let relaunched = store(FakeFetcher { _ in throw URLError(.notConnectedToInternet) }, folder: folder)

        #expect(relaunched.primaryReport?.current.temperature == 7.4)
    }
}

/// A value shared with a `@Sendable` closure in a test.
final class Flag: @unchecked Sendable {
    // @unchecked: the lock guards every access to `stored`.
    private let lock = NSLock()
    private var stored: Bool

    init(_ value: Bool) {
        stored = value
    }

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
