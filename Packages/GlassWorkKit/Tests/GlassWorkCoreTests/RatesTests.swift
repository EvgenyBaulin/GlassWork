import Foundation
@testable import GlassWorkCore
import Testing

private let usdRub = RatePair(base: "USD", quote: "RUB")
private let eurUsd = RatePair(base: "EUR", quote: "USD")
private let btcUsd = RatePair(base: "BTC", quote: "USD")
private let now = Date(timeIntervalSince1970: 1_793_750_000)

struct RatePairTests {
    @Test(arguments: ["USD/RUB", "usd rub", "usdrub", " Usd / Rub "])
    func readsWhatPeopleType(text: String) {
        #expect(RatePair(parsing: text) == usdRub)
    }

    @Test(arguments: ["", "USD", "USD/RUBLE", "ДОЛ/РУБ"])
    func rejectsTheRest(text: String) {
        #expect(RatePair(parsing: text) == nil)
    }

    @Test(arguments: [
        ("USD/RUB", RateSource.cbr), ("GBP/RUB", .cbr), ("EUR/USD", .frankfurter), ("USD/JPY", .frankfurter),
        ("BTC/USD", .coinGecko), ("ETH/EUR", .coinGecko), ("BTC/RUB", .coinGecko),
    ])
    func routesToTheServiceThatHasIt(text: String, expected: RateSource) {
        #expect(RatePair(parsing: text)?.source == expected)
    }

    @Test(arguments: ["RUB/USD", "USD/USD", "XXX/RUB", "BTC/JPY", "ILS/XDR"])
    func nobodyPublishesThese(text: String) {
        #expect(RatePair(parsing: text)?.source == nil)
    }

    @Test func theChosenBarPairFallsBackWhenItIsRemoved() {
        var settings = RatesSettings()
        settings.barPair = eurUsd
        #expect(settings.shownPair == eurUsd)

        settings.pairs.removeAll { $0 == eurUsd }
        #expect(settings.shownPair == usdRub)
    }
}

struct CBRParserTests {
    @Test func readsTheDay() throws {
        let day = try CBR.day(from: fixture("cbr-daily.json"))

        #expect(day.rates["USD"] == 81.6699)
        #expect(day.previousRates["USD"] == 80.9734)
        #expect(day.date == ISO8601DateFormatter().date(from: "2026-11-04T11:30:00+03:00"))
    }

    @Test func dividesByTheNominal() throws {
        let day = try CBR.day(from: fixture("cbr-daily.json"))

        #expect(abs((day.rates["JPY"] ?? 0) - 0.517553) < 0.000_001)
    }

    @Test func dayChangeComesFromThePreviousValue() throws {
        let day = try CBR.day(from: fixture("cbr-daily.json"))
        let quote = try #require(CBR.quote(for: usdRub, days: [day]))

        #expect(abs(quote.change - 0.6965) < 0.000_1)
        #expect(quote.isUp)
        #expect(abs(quote.changeShare - 0.6965 / 80.9734) < 0.000_01)
    }

    @Test func followsItsOwnArchiveLinks() throws {
        let day = try CBR.day(from: fixture("cbr-daily.json"))

        #expect(CBR.archiveURL(day.previousURL)?.absoluteString
            == "https://www.cbr-xml-daily.ru/archive/2026/11/03/daily_json.js")
    }

    @Test(arguments: ["//evil.example/daily_json.js", "http://www.cbr-xml-daily.ru/a.js", "", "not a url"])
    func followsNothingElse(link: String) {
        #expect(CBR.archiveURL(link) == nil)
    }

    @Test func keepsTheNewestDaysWithoutRepeats() throws {
        let day = try CBR.day(from: fixture("cbr-daily.json"))
        var days: [CBRDay] = []
        for offset in 0 ..< 12 {
            var older = day
            older.date = day.date.addingTimeInterval(Double(-offset) * 86400)
            days = CBR.merged(older, into: days)
        }

        let merged = CBR.merged(day, into: days)

        #expect(merged.count == CBR.historyDays)
        #expect(merged.first?.date == day.date)
    }
}

struct FrankfurterParserTests {
    @Test func usesTheLastTwoDays() throws {
        let quotes = try Frankfurter.quotes(from: fixture("frankfurter-series.json"), pairs: [eurUsd])
        let quote = try #require(quotes.first)
        let previous = try #require(quote.history.dropLast().last)

        #expect(quote.source == .frankfurter)
        #expect(quote.value == quote.history.last?.value)
        #expect(abs(quote.change - (quote.value - previous.value)) < 0.000_001)
        #expect(quote.history.count > 5)
    }

    @Test func historyRunsForwardInTime() throws {
        let quotes = try Frankfurter.quotes(from: fixture("frankfurter-series.json"), pairs: [eurUsd])
        let dates = try #require(quotes.first).history.map(\.date)

        #expect(dates == dates.sorted())
    }

    @Test func aPairWithoutDataIsLeftOut() throws {
        let missing = RatePair(base: "EUR", quote: "JPY")

        #expect(try Frankfurter.quotes(from: fixture("frankfurter-series.json"), pairs: [missing]).isEmpty)
    }

    @Test func oneRequestCoversAllQuotesOfABase() throws {
        let url = try #require(Frankfurter.seriesURL(base: "EUR", quotes: ["USD", "GBP"], now: now))

        #expect(url.host() == "api.frankfurter.dev")
        #expect(url.query()?.contains("symbols=GBP,USD") == true)
    }
}

struct CoinGeckoParserTests {
    @Test func turnsThePercentIntoAnAmount() throws {
        let quotes = try CoinGecko.quotes(from: fixture("coingecko-price.json"), pairs: [btcUsd])
        let quote = try #require(quotes.first)

        #expect(quote.value == 77818)
        #expect(abs(quote.changeShare - 0.014_273_786) < 0.000_001)
        #expect(quote.date == Date(timeIntervalSince1970: 1_793_748_974))
    }

    @Test func aMissingChangeReadsAsNoChange() throws {
        let data = Data(#"{"bitcoin":{"usd":100,"usd_24h_change":null}}"#.utf8)

        #expect(try CoinGecko.quotes(from: data, pairs: [btcUsd]).first?.change == 0)
    }

    @Test func readsTheChart() throws {
        let history = try CoinGecko.history(from: fixture("coingecko-chart.json"))

        #expect(history.count == 8)
        #expect(history.first?.date == Date(timeIntervalSince1970: 1_793_145_600))
    }
}

struct RateFormatTests {
    private let locale = Locale(identifier: "en_US")

    @Test(arguments: [(68420.4, "68,420"), (81.4221, "81.42"), (1.15581, "1.1558"), (0.5175, "0.5175")])
    func decimalsFollowTheSize(value: Double, expected: String) {
        #expect(Format.exchangeRate(value, locale: locale) == expected)
    }

    @Test func aChangeUsesTheDigitsOfItsRate() {
        #expect(Format.exchangeRateChange(-0.24, of: 81.42, locale: locale) == "0.24")
        #expect(Format.exchangeRateChange(0.0012, of: 1.1558, locale: locale) == "0.0012")
    }

    @Test func percentCarriesItsSign() {
        #expect(Format.signedPercent(0.003, locale: locale) == "+0.3%")
        #expect(Format.signedPercent(-0.019, locale: locale) == "−1.9%")
    }
}

@MainActor
struct RatesStoreTests {
    private func store(_ fetcher: FakeFetcher, folder: URL = temporaryFolder()) -> RatesStore {
        RatesStore(fetcher: fetcher, store: SnapshotStore(directory: folder))
    }

    /// Every service answers from its fixture; archive days of the Bank of Russia are not published.
    private nonisolated static func answer(_ url: URL) throws -> Data {
        switch url.host() {
        case "api.frankfurter.dev": return try fixture("frankfurter-series.json")
        case "api.coingecko.com":
            return try fixture(url.path().contains("market_chart") ? "coingecko-chart.json" : "coingecko-price.json")
        default:
            if url.path().contains("archive") {
                throw HTTPError.status(404)
            }
            return try fixture("cbr-daily.json")
        }
    }

    @Test func inactiveStoreStaysOffTheNetwork() async {
        let fetcher = FakeFetcher(answer: Self.answer)
        let store = store(fetcher)

        store.tick(at: now)
        await Task.yield()

        #expect(fetcher.requests.isEmpty)
    }

    @Test func fillsEveryPairFromItsService() async {
        let store = store(FakeFetcher(answer: Self.answer))

        await store.refresh(at: now)

        #expect(store.status == .ready)
        #expect(store.snapshot.quotes.count == 5)
        #expect(store.snapshot.quote(for: btcUsd)?.history.count == 8)
        #expect(store.snapshot.updatedAt == now)
    }

    @Test func onlyAsksTheNamedServices() async {
        let fetcher = FakeFetcher(answer: Self.answer)
        let store = store(fetcher)

        await store.refresh(at: now)

        let hosts = Set(fetcher.requests.compactMap { $0.host() })
        #expect(hosts == ["www.cbr-xml-daily.ru", "api.frankfurter.dev", "api.coingecko.com"])
    }

    @Test func aMissingArchiveDayDoesNotFailTheRefresh() async {
        let store = store(FakeFetcher(answer: Self.answer))

        await store.refresh(at: now)

        #expect(store.failedSources.isEmpty)
        #expect(store.snapshot.quote(for: usdRub)?.history.count == 1)
    }

    @Test func oneServiceDownLeavesTheOthersLive() async {
        let fetcher = FakeFetcher { url in
            if url.host() == "api.coingecko.com" {
                throw HTTPError.status(429)
            }
            return try Self.answer(url)
        }
        let store = store(fetcher)

        await store.refresh(at: now)

        #expect(store.status == .failed)
        #expect(store.failedSources == [.coinGecko])
        #expect(store.isUnavailable(btcUsd))
        #expect(!store.isUnavailable(usdRub))
        #expect(!store.isStale)
        #expect(store.snapshot.quote(for: usdRub) != nil)
    }

    @Test func noConnectionKeepsEverythingAndItsDate() async {
        let isOnline = Flag(true)
        let store = store(FakeFetcher { url in
            guard isOnline.value else { throw URLError(.notConnectedToInternet) }
            return try Self.answer(url)
        })
        await store.refresh(at: now)

        isOnline.value = false
        await store.refresh(at: now.addingTimeInterval(1800))

        #expect(store.isStale)
        #expect(store.snapshot.updatedAt == now)
        #expect(store.snapshot.quotes.count == 5)
        #expect(!store.isUnavailable(btcUsd))
    }

    @Test func aRemovedPairGoesAwayOnTheNextRefresh() async {
        let store = store(FakeFetcher(answer: Self.answer))
        await store.refresh(at: now)

        var settings = store.settings
        settings.pairs.removeAll { $0 == eurUsd }
        store.apply(settings)
        await store.refresh(at: now)

        #expect(store.snapshot.quote(for: eurUsd) == nil)
    }

    @Test func thePublishedDaysAreNotDownloadedAgain() async {
        let archive = Data(
            #"{"Date":"2026-11-03T11:30:00+03:00","Valute":{"USD":{"Nominal":1,"Value":80.97,"Previous":80.5}}}"#.utf8
        )
        let fetcher = FakeFetcher { url in
            url.path().contains("archive") ? archive : try Self.answer(url)
        }
        let folder = temporaryFolder()
        await store(fetcher, folder: folder).refresh(at: now)
        let first = fetcher.requests.count { $0.path().contains("archive") }

        await store(fetcher, folder: folder).refresh(at: now)
        let second = fetcher.requests.count { $0.path().contains("archive") } - first

        // The chain ends after one archive day here, so a second run has only that link left to try.
        #expect(first == 1)
        #expect(second == 0)
    }
}
