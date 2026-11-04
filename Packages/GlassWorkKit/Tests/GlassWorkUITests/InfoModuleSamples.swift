import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI

let sampleNow = Date(timeIntervalSince1970: 1_793_773_800)

private struct NoNetwork: HTTPFetching {
    func data(from _: URL) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}

/// CoinGecko refuses, the others answer: the design's "source error" state.
private struct CoinGeckoDown: HTTPFetching {
    private static let cbr = """
    {"Date":"2026-11-04T11:30:00+03:00","Valute":{
    "USD":{"Nominal":1,"Value":81.42,"Previous":81.18},"EUR":{"Nominal":1,"Value":94.10,"Previous":94.28}}}
    """
    private static let ecb = #"{"rates":{"2026-11-03":{"USD":1.1546},"2026-11-04":{"USD":1.1558}}}"#

    func data(from url: URL) async throws -> Data {
        switch url.host() {
        case "api.coingecko.com": throw HTTPError.status(429)
        case "api.frankfurter.dev": return Data(Self.ecb.utf8)
        default:
            if url.path().contains("archive") {
                throw HTTPError.status(404)
            }
            return Data(Self.cbr.utf8)
        }
    }
}

func sampleFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(
        path: "GlassWorkUI-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
}

/// The same data as the design's sample, in a fixed zone so times do not depend on the Mac.
func sampleReport() -> WeatherReport {
    let place = WeatherPlace(id: 524_901, name: "Moscow", country: "Russia", latitude: 55.75, longitude: 37.62)
    let conditions: [WeatherCondition] = [.partlyCloudy, .partlyCloudy, .cloudy, .cloudy, .rain, .rain, .cloudy]
    let hours = conditions.enumerated().map { index, condition in
        HourForecast(
            date: sampleNow.addingTimeInterval(Double(index) * 3600 - 1800),
            temperature: 12 + Double(index % 3),
            condition: condition,
            isDay: true
        )
    }
    let days = [
        (8.0, 14.0, WeatherCondition.partlyCloudy), (7, 12, .rain), (6, 11, .rain), (5, 10, .cloudy), (4, 12, .clear),
        (6, 14, .partlyCloudy), (7, 13, .cloudy),
    ].enumerated().map { index, day in
        DayForecast(
            date: sampleNow.addingTimeInterval(Double(index) * 86400),
            low: day.0,
            high: day.1,
            condition: day.2
        )
    }
    return WeatherReport(
        place: place,
        timeZone: "Europe/Moscow",
        fetchedAt: sampleNow,
        current: CurrentWeather(
            temperature: 12, feelsLike: 10, humidity: 71, windSpeed: 4, uvIndex: 1, condition: .partlyCloudy,
            isDay: true
        ),
        hours: hours,
        days: days
    )
}

func sampleQuote(_ text: String, source: RateSource, values: [Double]) -> RateQuote? {
    guard let pair = RatePair(parsing: text), let value = values.last else { return nil }
    let history = values.enumerated().map { index, point in
        RatePoint(date: sampleNow.addingTimeInterval(Double(index - values.count) * 86400), value: point)
    }
    return RateQuote(
        pair: pair,
        source: source,
        value: value,
        change: value - values[values.count - 2],
        history: history,
        date: sampleNow
    )
}

func sampleRates() -> RatesSnapshot {
    let quotes = [
        sampleQuote("USD/RUB", source: .cbr, values: [80.1, 80.6, 80.3, 81.0, 80.8, 81.18, 81.42]),
        sampleQuote("EUR/RUB", source: .cbr, values: [95.0, 94.6, 94.9, 94.4, 94.5, 94.28, 94.10]),
        sampleQuote("EUR/USD", source: .frankfurter, values: [1.148, 1.151, 1.149, 1.153, 1.152, 1.1546, 1.1558]),
        sampleQuote("BTC/USD", source: .coinGecko, values: [70400, 71100, 70500, 69800, 70000, 69730, 68420]),
        sampleQuote("ETH/USD", source: .coinGecko, values: [2320, 2350, 2330, 2380, 2400, 2374, 2412]),
    ].compactMap(\.self)
    return RatesSnapshot(quotes: quotes, updatedAt: sampleNow)
}

@MainActor
func weatherStore(_ report: WeatherReport? = sampleReport()) -> WeatherStore {
    let snapshots = SnapshotStore(directory: sampleFolder())
    try? snapshots.write(WeatherSnapshot(reports: [report].compactMap(\.self)), for: WeatherSnapshot.key)
    let store = WeatherStore(fetcher: NoNetwork(), store: snapshots)
    var settings = WeatherSettings()
    settings.places = [report?.place].compactMap(\.self)
    store.apply(settings)
    return store
}

@MainActor
func ratesStore(isMonochrome: Bool = false, isOffline: Bool = false, isCryptoDown: Bool = false) async -> RatesStore {
    let snapshots = SnapshotStore(directory: sampleFolder())
    try? snapshots.write(sampleRates(), for: RatesSnapshot.key)
    let fetcher: any HTTPFetching = isCryptoDown ? CoinGeckoDown() : NoNetwork()
    let store = RatesStore(fetcher: fetcher, store: snapshots)
    var settings = RatesSettings()
    settings.isMonochrome = isMonochrome
    store.apply(settings)
    if isOffline || isCryptoDown {
        await store.refresh(at: sampleNow)
    }
    return store
}

private func sampleEntry(_ kind: ClipboardKind, _ text: String, app: String, age: TimeInterval) -> ClipboardEntry {
    ClipboardEntry(
        kind: kind,
        text: text,
        byteCount: text.utf8.count,
        appName: app,
        date: sampleNow.addingTimeInterval(-age),
        fingerprint: text
    )
}

@MainActor
func clipboardStore(isRecording: Bool = true, pinned: Bool = true) -> ClipboardStore {
    let store = ClipboardStore(folder: sampleFolder())
    var settings = ClipboardSettings()
    settings.isRecording = isRecording
    store.apply(settings)
    let samples = [
        sampleEntry(.color, "#6B5BB5", app: "Colours", age: 1200),
        sampleEntry(.file, "/Users/me/Documents/invoice-oct.pdf", app: "Finder", age: 720),
        sampleEntry(.text, "Meeting moved to 15:00 — see you there", app: "Messages", age: 240),
        sampleEntry(.link, "https://github.com/acme/glasswork/pull/42", app: "Safari", age: 60),
    ]
    samples.forEach { store.add(ClipboardCapture(entry: $0)) }
    if pinned, let last = store.history.entries.last {
        store.togglePin(last)
    }
    return store
}

/// A view on the panel's dark or light background, sized by its own content.
@MainActor
func assertPanel(_ view: some View, width: CGFloat = 340, height: CGFloat? = nil, dark: Bool, name: String) {
    let scheme: ColorScheme = dark ? .dark : .light
    let background = dark ? Color(red: 0.16, green: 0.15, blue: 0.24) : Color(white: 0.93)
    let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).background(background))
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = CGRect(x: 0, y: 0, width: width, height: height ?? 100)
    // A window that is never shown: a List loads its rows only once it is in one.
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.appearance = host.appearance
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    if height == nil {
        window.setContentSize(CGSize(width: width, height: host.fittingSize.height))
        host.layoutSubtreeIfNeeded()
    }
    let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
    withSnapshotTesting(record: record ? .all : .missing) {
        assertSnapshot(of: host, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
    }
}
