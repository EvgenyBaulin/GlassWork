import Foundation
@testable import GlassWorkCore
import Testing

struct SunLocationTests {
    private let tokyo = WeatherPlace(id: 1, name: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.69)
    private let lisbon = WeatherPlace(id: 2, name: "Lisbon", country: "Portugal", latitude: 38.72, longitude: -9.14)

    @Test func noPlacesMeansNoPlace() {
        #expect(SunLocation.place(in: [], chosen: nil) == nil)
        #expect(SunLocation.place(in: [], chosen: 1) == nil)
    }

    @Test func theFirstPlaceIsUsedByDefault() {
        #expect(SunLocation.place(in: [tokyo, lisbon], chosen: nil) == tokyo)
    }

    @Test func thePickedPlaceWins() {
        #expect(SunLocation.place(in: [tokyo, lisbon], chosen: 2) == lisbon)
    }

    @Test func aPlaceRemovedFromWeatherFallsBackToTheFirst() {
        #expect(SunLocation.place(in: [tokyo, lisbon], chosen: 99) == tokyo)
    }

    @Test func theMonitorHasNoBuiltInCity() async {
        let monitor = await SystemMonitor(weather: WeatherStore(
            fetcher: FakeFetcher { _ in Data() },
            store: SnapshotStore(directory: temporaryFolder())
        ))
        #expect(await monitor.sunPlace == nil)
    }
}

struct NextSunEventTests {
    private let latitude = 55.75
    private let longitude = 37.62

    /// 2026-11-04 at the given UTC hour.
    private func utc(_ hour: Double) -> Date {
        Date(timeIntervalSince1970: 1_793_750_400 + hour * 3600)
    }

    private func next(_ shows: SunShows, _ hour: Double) -> NextSunEvent? {
        Astronomy.nextEvent(shows, after: utc(hour), latitude: latitude, longitude: longitude)
    }

    @Test func beforeSunriseItIsSunrise() {
        #expect(next(.next, 1)?.event == .sunrise)
    }

    @Test func duringTheDayItIsSunset() {
        #expect(next(.next, 9)?.event == .sunset)
    }

    /// The old code looked at today only, so the item went blank for the whole evening.
    @Test func afterSunsetItIsTomorrowsSunrise() throws {
        let event = try #require(next(.next, 20))
        #expect(event.event == .sunrise)
        #expect(event.date > utc(20))
        #expect(event.date < utc(36))
    }

    @Test func askingForOneEventSkipsTheOther() {
        #expect(next(.sunrise, 9)?.event == .sunrise)
        #expect(next(.sunset, 1)?.event == .sunset)
    }

    @Test func theEventIsAlwaysAhead() throws {
        for hour in stride(from: 0.0, to: 48, by: 3) {
            let event = try #require(next(.next, hour))
            #expect(event.date > utc(hour))
            #expect(event.date.timeIntervalSince(utc(hour)) < 86400)
        }
    }

    @Test func aPolarNightHasNoNextEvent() {
        let event = Astronomy.nextEvent(.next, after: utc(12), latitude: 85, longitude: 0)
        #expect(event == nil)
    }
}
