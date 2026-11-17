import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

private let miniNow = Date(timeIntervalSince1970: 1_794_831_360)

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct IslandMiniWidgetsSnapshotTests {
    private let geometry = IslandGeometry(screen: IslandScreen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32,
        auxiliaryLeftWidth: 628, auxiliaryRightWidth: 628, menuBarHeight: 32
    ))

    private var input: IslandInput {
        var input = IslandInput()
        input.calendarEvents = [AgendaEvent(
            id: "review", title: "Design review", start: miniNow.addingTimeInterval(2640),
            end: miniNow.addingTimeInterval(4440)
        )]
        input.weather = WeatherReport(
            place: WeatherPlace(id: 1, name: "Moscow", country: "RU", latitude: 55.7, longitude: 37.6),
            timeZone: "Europe/Moscow", fetchedAt: miniNow,
            current: CurrentWeather(
                temperature: 7, feelsLike: 5, humidity: 80, windSpeed: 3, uvIndex: 0, condition: .cloudy, isDay: true
            ),
            hours: [], days: [DayForecast(date: miniNow, low: 3, high: 9, condition: .cloudy)]
        )
        input.rates = [
            RateQuote(
                pair: RatePair(base: "USD", quote: "RUB"), source: .cbr, value: 92.4, change: 0, history: [],
                date: miniNow
            ),
            RateQuote(
                pair: RatePair(base: "EUR", quote: "RUB"), source: .cbr, value: 99.12, change: 0, history: [],
                date: miniNow
            ),
        ]
        input.cpu = CPUSample(total: 0.23, user: 0.15, system: 0.08, idle: 0.77, cores: [])
        return input
    }

    private func render(_ store: IslandStore, name: String, dark: Bool, height: CGFloat) {
        var island = IslandView(store: store, geometry: geometry)
        island.fixedNow = miniNow
        let view = ZStack(alignment: .top) {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.25, green: 0.24, blue: 0.48), Color(red: 0.52, green: 0.40, blue: 0.73)]
                    : [Color(red: 0.96, green: 0.95, blue: 1), Color(red: 0.82, green: 0.78, blue: 0.94)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            island
        }
        .frame(width: 620, height: height)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 3 * 3600)!)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        snapshotPanel(view, name: name, dark: dark, testName: "miniWidgets")
    }

    private func openedStore() -> IslandStore {
        let store = IslandStore()
        store.lifecycle.opensWidgets = true
        store.update(input: input, now: miniNow)
        store.lifecycle.clicked()
        store.lifecycle.clicked()
        return store
    }

    @Test func expandedGrid() {
        for dark in [true, false] {
            render(openedStore(), name: "expanded", dark: dark, height: 240)
        }
    }

    @Test func editList() {
        for dark in [true, false] {
            let store = openedStore()
            store.isEditingWidgets = true
            render(store, name: "edit", dark: dark, height: 420)
        }
    }
}
