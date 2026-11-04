import Foundation

/// Who publishes a rate. Each of these works without a key.
public enum RateSource: String, Codable, Sendable, CaseIterable {
    case cbr, frankfurter, coinGecko

    private static let crypto: Set<String> = ["BTC", "ETH"]
    private static let cryptoQuotes: Set<String> = ["USD", "EUR", "RUB"]
    private static let cbrCurrencies: Set<String> = [
        "AED", "AMD", "AUD", "AZN", "BDT", "BHD", "BOB", "BRL", "BYN", "CAD", "CHF", "CNY", "CUP", "CZK",
        "DKK", "DZD", "EGP", "ETB", "EUR", "GBP", "GEL", "HKD", "HUF", "IDR", "INR", "IRR", "JPY", "KGS",
        "KRW", "KZT", "MDL", "MMK", "MNT", "NGN", "NOK", "NZD", "OMR", "PLN", "QAR", "RON", "RSD", "SAR",
        "SEK", "SGD", "THB", "TJS", "TMT", "TRY", "UAH", "USD", "UZS", "VND", "XDR", "ZAR",
    ]
    private static let frankfurterCurrencies: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR",
        "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY",
        "USD", "ZAR",
    ]

    /// The one service that can answer for a pair, or nil when none can. The ECB does not publish RUB.
    public static func route(_ pair: RatePair) -> RateSource? {
        if crypto.contains(pair.base) {
            return cryptoQuotes.contains(pair.quote) ? .coinGecko : nil
        }
        if pair.quote == "RUB" {
            return cbrCurrencies.contains(pair.base) ? .cbr : nil
        }
        let isKnown = frankfurterCurrencies.contains(pair.base) && frankfurterCurrencies.contains(pair.quote)
        return isKnown && pair.base != pair.quote ? .frankfurter : nil
    }
}

public struct RatePair: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var base: String
    public var quote: String

    public init(base: String, quote: String) {
        self.base = base
        self.quote = quote
    }

    /// Reads "usd/rub", "USD RUB" or "USDRUB".
    public init?(parsing text: String) {
        let letters = text.uppercased().filter(\.isLetter)
        guard letters.count == 6, letters.allSatisfy(\.isASCII) else { return nil }
        self.init(base: String(letters.prefix(3)), quote: String(letters.suffix(3)))
    }

    public var id: String {
        "\(base)/\(quote)"
    }

    public var source: RateSource? {
        RateSource.route(self)
    }
}

public struct RatesSettings: Codable, Sendable, Equatable {
    public static let defaultPairs = [
        RatePair(base: "USD", quote: "RUB"), RatePair(base: "EUR", quote: "RUB"),
        RatePair(base: "EUR", quote: "USD"), RatePair(base: "BTC", quote: "USD"),
        RatePair(base: "ETH", quote: "USD"),
    ]

    public var pairs = RatesSettings.defaultPairs
    /// The pair shown in the menu bar. Falls back to the first one.
    public var barPair: RatePair?
    /// Draws the day change in the bar's own color instead of green and red.
    public var isMonochrome = false

    public init() {}

    public var shownPair: RatePair? {
        barPair.flatMap { pairs.contains($0) ? $0 : nil } ?? pairs.first
    }

    private enum CodingKeys: String, CodingKey {
        case pairs, barPair, isMonochrome
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairs = try container.decodeIfPresent([RatePair].self, forKey: .pairs) ?? Self.defaultPairs
        barPair = try container.decodeIfPresent(RatePair.self, forKey: .barPair)
        isMonochrome = try container.decodeIfPresent(Bool.self, forKey: .isMonochrome) ?? false
    }
}

public struct RatePoint: Codable, Sendable, Equatable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct RateQuote: Codable, Sendable, Equatable, Identifiable {
    public var pair: RatePair
    public var source: RateSource
    public var value: Double
    /// Difference from the previous published value: yesterday's, or 24 hours ago for crypto.
    public var change: Double
    public var history: [RatePoint]
    /// When the source published this value.
    public var date: Date

    public init(pair: RatePair, source: RateSource, value: Double, change: Double, history: [RatePoint], date: Date) {
        self.pair = pair
        self.source = source
        self.value = value
        self.change = change
        self.history = history
        self.date = date
    }

    public var id: String {
        pair.id
    }

    /// Change as a share of the previous value, so 0.003 reads as +0.3%.
    public var changeShare: Double {
        let previous = value - change
        return previous == 0 ? 0 : change / previous
    }

    public var isUp: Bool {
        change >= 0
    }
}

/// What the app keeps for the stale state, and what a widget can read later.
public struct RatesSnapshot: Codable, Sendable, Equatable {
    public static let key = "rates"

    public var quotes: [RateQuote] = []
    /// Published days never change, so only the missing ones are ever downloaded.
    public var cbrDays: [CBRDay] = []
    public var updatedAt: Date?

    public init(quotes: [RateQuote] = [], cbrDays: [CBRDay] = [], updatedAt: Date? = nil) {
        self.quotes = quotes
        self.cbrDays = cbrDays
        self.updatedAt = updatedAt
    }

    public func quote(for pair: RatePair) -> RateQuote? {
        quotes.first { $0.pair == pair }
    }
}

public extension Format {
    /// Big numbers lose their decimals, small ones keep four: 68,420 · 81.42 · 1.1558.
    static func exchangeRate(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(rateDigits(value))).locale(locale))
    }

    /// Uses the digits of the rate itself, so a change lines up with the value above it.
    static func exchangeRateChange(_ change: Double, of value: Double, locale: Locale = .current) -> String {
        abs(change).formatted(.number.precision(.fractionLength(rateDigits(value))).locale(locale))
    }

    static func signedPercent(_ share: Double, locale: Locale = .current) -> String {
        let text = abs(share * 100).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return "\(share < 0 ? "−" : "+")\(text)%"
    }

    private static func rateDigits(_ value: Double) -> Int {
        switch abs(value) {
        case 1000...: 0
        case 10...: 2
        default: 4
        }
    }
}
