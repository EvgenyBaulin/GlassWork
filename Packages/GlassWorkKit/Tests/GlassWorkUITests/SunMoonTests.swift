import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
struct SunMoonItemTests {
    private let tokyo = WeatherPlace(id: 1, name: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.69)
    private let utc = TimeZone(identifier: "UTC") ?? .current
    /// 2026-11-04 at noon UTC.
    private let noon = Date(timeIntervalSince1970: 1_793_750_400 + 12 * 3600)

    @Test func withoutACityItIsDimmedAndNamesNoTime() {
        let item = ItemContent.sunMoon(nil, zone: utc, at: noon, options: [:])
        #expect(item.figure == "—")
        #expect(item.isDimmed)
    }

    @Test func itNamesTheCityInItsTooltip() {
        let item = ItemContent.sunMoon(tokyo, zone: utc, at: noon, options: [:])
        #expect(item.detail == "Tokyo")
        #expect(!item.isDimmed)
    }

    @Test func theArrowShowsWhichEvent() {
        let sunrise = ItemContent.sunMoon(tokyo, zone: utc, at: noon, options: [ItemOption.sunShows: "sunrise"])
        let sunset = ItemContent.sunMoon(tokyo, zone: utc, at: noon, options: [ItemOption.sunShows: "sunset"])
        #expect(sunrise.figure.hasPrefix("↑"))
        #expect(sunset.figure.hasPrefix("↓"))
    }

    @Test func aDifferentCityGivesADifferentTime() {
        let lisbon = WeatherPlace(id: 2, name: "Lisbon", country: "Portugal", latitude: 38.72, longitude: -9.14)
        let shows = [ItemOption.sunShows: "sunrise"]
        let first = ItemContent.sunMoon(tokyo, zone: utc, at: noon, options: shows).figure
        let second = ItemContent.sunMoon(lisbon, zone: utc, at: noon, options: shows).figure
        #expect(first != second)
    }

    @Test func theTimeReadsInTheZoneAsked() {
        let tokyoZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let shows = [ItemOption.sunShows: "sunrise"]
        let inUTC = ItemContent.sunMoon(tokyo, zone: utc, at: noon, options: shows).figure
        let inTokyo = ItemContent.sunMoon(tokyo, zone: tokyoZone, at: noon, options: shows).figure
        #expect(inUTC != inTokyo)
    }

    @Test func aSnapshotWithoutAPlaceIsNotASunPlace() {
        #expect(SunPlace(WidgetSnapshot(date: noon)) == nil)
    }

    @Test func aSnapshotCarriesThePlaceAcross() throws {
        var snapshot = WidgetSnapshot(date: noon)
        snapshot.place = tokyo
        let place = try #require(SunPlace(snapshot))
        #expect(place.name == "Tokyo")
        #expect(place.latitude == tokyo.latitude)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct SunMoonSnapshotTests {
    private let moment = Date(timeIntervalSince1970: 1_793_750_400 + 12 * 3600)

    /// No network and a folder of its own, so nothing reaches the real snapshots.
    private func weather(_ places: [WeatherPlace]) -> WeatherStore {
        let store = WeatherStore(fetcher: NoNetwork(), store: SnapshotStore(directory: sampleFolder()))
        var settings = WeatherSettings()
        settings.places = places
        store.apply(settings)
        return store
    }

    @Test(arguments: [true, false])
    func panelWithoutACity(dark: Bool) {
        let monitor = SystemMonitor(weather: weather([]))
        snapshotPanel(SunMoonPanel(monitor: monitor, moment: moment), name: "no-city", dark: dark)
    }

    @Test(arguments: [true, false])
    func panelWithACity(dark: Bool) {
        let place = WeatherPlace(id: 1, name: "Tokyo", country: "Japan", latitude: 35.68, longitude: 139.69)
        let monitor = SystemMonitor(weather: weather([place]))
        snapshotPanel(SunMoonPanel(monitor: monitor, moment: moment), name: "city", dark: dark)
    }

    @Test(arguments: [true, false])
    func widgetWithoutACity(dark: Bool) {
        let view = NoCityMessage().frame(width: 158, height: 158)
        snapshotPanel(view, name: "widget", dark: dark)
    }
}
