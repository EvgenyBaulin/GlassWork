import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Panels of Weather, Rates and Clipboard in the states the design draws, in both themes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct InfoModuleSnapshotTests {
    @Test(arguments: [true, false])
    func weatherForecast(dark: Bool) {
        assertPanel(WeatherPanel(store: weatherStore(), now: sampleNow), dark: dark, name: "weather")
    }

    @Test(arguments: [true, false])
    func weatherFirstRunAsksBeforeUsingLocation(dark: Bool) {
        assertPanel(WeatherPanel(store: weatherStore(nil), now: sampleNow), dark: dark, name: "weather-first-run")
    }

    @Test(arguments: [true, false])
    func weatherOfflineShowsTheLastData(dark: Bool) async {
        let store = weatherStore()
        await store.refresh(at: sampleNow)
        assertPanel(WeatherPanel(store: store, now: sampleNow), dark: dark, name: "weather-offline")
    }

    @Test(arguments: [true, false])
    func weatherOfflineSaysWhichDayTheDataIsFrom(dark: Bool) async {
        let store = weatherStore()
        await store.refresh(at: sampleNow)
        let nextDay = sampleNow.addingTimeInterval(86400)
        assertPanel(WeatherPanel(store: store, now: nextDay), dark: dark, name: "weather-offline-old")
    }

    @Test(arguments: [true, false])
    func dayRangeAnswersToTheCursor(dark: Bool) {
        let report = sampleReport()
        let view = WeatherForecast(report: report, hoveredDay: report.days[3].date).padding(16)
        assertPanel(view, dark: dark, name: "weather-day-hover")
    }

    @Test(arguments: [true, false])
    func weatherLocations(dark: Bool) {
        let store = weatherStore()
        var settings = store.settings
        let lisbon = WeatherPlace(id: 1, name: "Lisbon", country: "Portugal", latitude: 38.7, longitude: -9.1)
        settings.places.append(lisbon)
        store.apply(settings)
        let view = WeatherLocations(store: store, onSelect: { _ in }).padding(16)
        assertPanel(view, dark: dark, name: "weather-locations")
    }

    @Test(arguments: [true, false])
    func ratesPanel(dark: Bool) async {
        await assertPanel(RatesPanel(store: ratesStore()), dark: dark, name: "rates")
    }

    @Test(arguments: [true, false])
    func ratesOfflineHidesTheChange(dark: Bool) async {
        await assertPanel(RatesPanel(store: ratesStore(isOffline: true)), dark: dark, name: "rates-offline")
    }

    @Test(arguments: [true, false])
    func ratesWithOneSourceDown(dark: Bool) async {
        await assertPanel(RatesPanel(store: ratesStore(isCryptoDown: true)), dark: dark, name: "rates-source-down")
    }

    @Test(arguments: [true, false])
    func rateChartAnswersToTheCursor(dark: Bool) throws {
        let quote = try #require(sampleRates().quotes.first)
        let hover = quote.history[quote.history.count - 3].date
        let row = RateRow(pair: quote.pair, quote: quote, initialHover: hover).padding(.bottom, 44)
        assertPanel(row, dark: dark, name: "rate-row-hover")
    }

    @Test(arguments: [true, false])
    func ratePairsEditor(dark: Bool) async {
        await assertPanel(RatePairsEditor(store: ratesStore()).padding(16), dark: dark, name: "rates-edit")
    }

    @Test(arguments: [true, false])
    func clipboardHistory(dark: Bool) {
        let view = ClipboardPanel(store: clipboardStore(), now: sampleNow)
        assertPanel(view, dark: dark, name: "clipboard")
    }

    @Test(arguments: [true, false])
    func clipboardOffUntilStarted(dark: Bool) {
        let view = ClipboardPanel(store: ClipboardStore(folder: sampleFolder()), now: sampleNow)
        assertPanel(view, dark: dark, name: "clipboard-off")
    }

    @Test(arguments: [true, false])
    func clipboardRowsCoverEveryKind(dark: Bool) {
        let store = clipboardStore(pinned: false)
        let rows = VStack(spacing: 2) {
            ForEach(store.history.entries) { entry in
                ClipboardRow(
                    entry: entry,
                    imageURL: nil,
                    query: "e",
                    shortcut: 1,
                    isHovered: entry.kind == .text,
                    now: sampleNow,
                    onUse: { _ in },
                    onPin: {},
                    onDelete: {}
                )
            }
        }
        assertPanel(rows.padding(8), dark: dark, name: "clipboard-rows")
    }

    @Test(arguments: [true, false])
    func quickPaste(dark: Bool) {
        let view = QuickPasteView(store: clipboardStore(), now: sampleNow, onUse: { _ in }, onCancel: {})
        assertPanel(view, width: 300, dark: dark, name: "quick-paste")
    }
}

/// The bitmap that really goes into the status item.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct InfoItemRendererSnapshotTests {
    private func assertItem(_ module: ModuleID, monitor: SystemMonitor, style: DisplayStyle, dark: Bool, name: String) {
        let renderer = MenuBarItemRenderer(module: module, style: style, numbers: .compact, monitor: monitor)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let width = MenuBarItemView.width(module: module, style: style, numbers: .compact, monitor: monitor)
        let view = NSImageView(frame: CGRect(x: 0, y: 0, width: width, height: 24))
        view.image = renderer.image(size: CGSize(width: width, height: 24), force: true)
        view.contentTintColor = .labelColor
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }

    @Test(arguments: [true, false])
    func ratesKeepsTheBarColorForTextAndColorsTheChange(dark: Bool) async {
        let monitor = await SystemMonitor(rates: ratesStore())
        assertItem(.rates, monitor: monitor, style: .figure, dark: dark, name: "rates-figure")
    }

    @Test(arguments: [true, false])
    func ratesMonochrome(dark: Bool) async {
        let monitor = await SystemMonitor(rates: ratesStore(isMonochrome: true))
        assertItem(.rates, monitor: monitor, style: .figure, dark: dark, name: "rates-mono")
    }

    @Test(arguments: [true, false])
    func ratesStale(dark: Bool) async {
        let monitor = await SystemMonitor(rates: ratesStore(isOffline: true))
        assertItem(.rates, monitor: monitor, style: .figure, dark: dark, name: "rates-stale")
    }

    @Test(arguments: [DisplayStyle.graph, .graphAndFigure, .labelled])
    func ratesOtherStyles(style: DisplayStyle) async {
        let monitor = await SystemMonitor(rates: ratesStore())
        assertItem(.rates, monitor: monitor, style: style, dark: true, name: "rates-\(style)")
    }

    @Test(arguments: [DisplayStyle.symbol, .figure, .graph, .graphAndFigure, .labelled])
    func weatherStyles(style: DisplayStyle) {
        let monitor = SystemMonitor(weather: weatherStore())
        assertItem(.weather, monitor: monitor, style: style, dark: true, name: "weather-\(style)")
    }

    @Test func clipboardCount() {
        let monitor = SystemMonitor(clipboard: clipboardStore())
        assertItem(.clipboard, monitor: monitor, style: .figure, dark: true, name: "clipboard-count")
    }
}

@MainActor
struct InfoItemContentTests {
    @Test func weatherShowsTheConditionAndTheCity() {
        let content = ItemContent.weather(weatherStore())

        #expect(content.symbol == "cloud.sun")
        #expect(content.label == "MOS")
        #expect(!content.isDimmed)
    }

    @Test func weatherWithoutDataIsADash() {
        #expect(ItemContent.weather(weatherStore(nil)).figure == "—")
    }

    @Test func staleWeatherFadesAndCrossesTheCloud() async {
        let store = weatherStore()
        await store.refresh(at: sampleNow)

        let content = ItemContent.weather(store)

        #expect(content.symbol == "icloud.slash")
        #expect(content.isDimmed)
        #expect(content.figure != "—")
    }

    @Test func ratesColorTheChange() async {
        let content = await ItemContent.rates(ratesStore())

        #expect(content.text(for: .figure) == "USD 81.42")
        #expect(content.text(for: .labelled) == "81.42")
        #expect(content.accent?.text == "↑ 0.3%")
        #expect(content.accent?.color == .green)
        #expect(!content.showsSymbol)
    }

    @Test func monochromeDropsTheColorButNotTheArrow() async {
        let content = await ItemContent.rates(ratesStore(isMonochrome: true))

        #expect(content.accent?.text == "↑ 0.3%")
        #expect(content.accent?.color == nil)
    }

    @Test func staleRatesHideTheChange() async {
        let content = await ItemContent.rates(ratesStore(isOffline: true))

        #expect(content.figure == "81.42")
        #expect(content.accent?.text == "—")
        #expect(content.isDimmed)
    }

    @Test func clipboardIsFadedUntilRecordingStarts() {
        #expect(ItemContent.clipboard(clipboardStore(isRecording: false)).isDimmed)
        #expect(!ItemContent.clipboard(clipboardStore()).isDimmed)
    }

    @Test func clipboardShowsTheCountAndKeepsTextPrivateByDefault() {
        #expect(ItemContent.clipboard(clipboardStore()).figure == "4")
    }

    @Test func aLongLastItemIsCut() {
        let store = clipboardStore()
        var settings = store.settings
        settings.showsLastItem = true
        store.apply(settings)

        let figure = ItemContent.clipboard(store).figure

        #expect(figure.count == 12)
        #expect(figure.hasSuffix("…"))
    }

    @Test func graphRangeFollowsTheData() throws {
        let range = try #require(ItemContent.padded([80, 82]))

        #expect(range.lowerBound > 79 && range.lowerBound < 80)
        #expect(range.upperBound > 82 && range.upperBound < 83)
    }

    @Test func aFlatLineStillHasARange() throws {
        let range = try #require(ItemContent.padded([81, 81]))

        #expect(range.lowerBound < 81 && range.upperBound > 81)
    }

    @Test func searchMarksEveryMatch() {
        let text = clipboardHighlighted("Port and port", query: "port")
        let marked = text.runs.filter { $0.backgroundColor != nil }

        #expect(marked.count == 2)
    }

    @Test(arguments: [("#6B5BB5", true), ("#FFF", true), ("#6B5BB5FF", true), ("#12", false), ("#GGGGGG", false)])
    func readsHexColors(text: String, isValid: Bool) {
        #expect((Color(hexText: text) != nil) == isValid)
    }

    @Test func dataFromTodayShowsOnlyTheTime() {
        let today = Format.dataTime(sampleNow, now: sampleNow.addingTimeInterval(60))
        let older = Format.dataTime(sampleNow, now: sampleNow.addingTimeInterval(86400))

        #expect(today == sampleNow.formatted(date: .omitted, time: .shortened))
        #expect(older.count > today.count)
        #expect(older.hasSuffix(today))
    }

    @Test func captionUsesTheGivenTime() {
        let entry = ClipboardEntry(
            kind: .text,
            text: "a",
            byteCount: 1,
            appName: "Notes",
            date: sampleNow.addingTimeInterval(-240),
            fingerprint: "a"
        )

        #expect(clipboardCaption(entry, now: sampleNow).hasPrefix("Notes · "))
        #expect(clipboardCaption(entry, now: sampleNow).contains("4"))
    }
}
