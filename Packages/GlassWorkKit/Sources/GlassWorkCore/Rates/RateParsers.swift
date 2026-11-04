import Foundation

/// One published day of the Bank of Russia. Rates are per single unit of the currency.
public struct CBRDay: Codable, Sendable, Equatable {
    public var date: Date
    public var previousURL: String?
    public var rates: [String: Double]
    public var previousRates: [String: Double]
}

/// `cbr-xml-daily.ru`: one file per published day, each linking to the one before.
public enum CBR {
    static let latestURL = URL(string: "https://www.cbr-xml-daily.ru/daily_json.js")
    /// Days kept for the small charts.
    static let historyDays = 8
    private static let host = "www.cbr-xml-daily.ru"

    public static func day(from data: Data) throws -> CBRDay {
        let response = try JSONDecoder().decode(CBRResponse.self, from: data)
        guard let date = ISO8601DateFormatter().date(from: response.date) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Bad date"))
        }
        // JPY and others are quoted per 10 or 100 units.
        return CBRDay(
            date: date,
            previousURL: response.previousURL,
            rates: response.valute.mapValues { $0.value / $0.nominal },
            previousRates: response.valute.mapValues { $0.previous / $0.nominal }
        )
    }

    /// The links in a response start with `//`. Only the service's own host is followed.
    public static func archiveURL(_ link: String?) -> URL? {
        guard let link, let url = URL(string: link.hasPrefix("//") ? "https:\(link)" : link),
              url.scheme == "https", url.host() == host
        else { return nil }
        return url
    }

    /// Adds a day to the known ones, newest first, without repeats.
    static func merged(_ day: CBRDay, into days: [CBRDay]) -> [CBRDay] {
        let others = days.filter { $0.date != day.date }
        return Array(([day] + others).sorted { $0.date > $1.date }.prefix(historyDays))
    }

    /// `days` is newest first, as `merged` leaves it.
    public static func quote(for pair: RatePair, days: [CBRDay]) -> RateQuote? {
        guard let latest = days.first, let value = latest.rates[pair.base] else { return nil }
        let previous = latest.previousRates[pair.base] ?? value
        let history = days.reversed().compactMap { day in
            day.rates[pair.base].map { RatePoint(date: day.date, value: $0) }
        }
        return RateQuote(
            pair: pair,
            source: .cbr,
            value: value,
            change: value - previous,
            history: history,
            date: latest.date
        )
    }
}

/// `frankfurter.dev`: the ECB's daily reference rates.
public enum Frankfurter {
    /// Weekends have no rates, so two weeks give about ten points.
    static let historyDays = 14

    static func seriesURL(base: String, quotes: [String], now: Date) -> URL? {
        let start = now.addingTimeInterval(-Double(historyDays) * 86400)
        var components = URLComponents(string: "https://api.frankfurter.dev/v1/\(dayFormatter().string(from: start))..")
        components?.queryItems = [
            URLQueryItem(name: "base", value: base),
            URLQueryItem(name: "symbols", value: quotes.sorted().joined(separator: ",")),
        ]
        return components?.url
    }

    public static func quotes(from data: Data, pairs: [RatePair]) throws -> [RateQuote] {
        let response = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
        let formatter = dayFormatter()
        let days = response.rates
            .compactMap { key, rates in formatter.date(from: key).map { (date: $0, rates: rates) } }
            .sorted { $0.date < $1.date }
        return pairs.compactMap { pair in
            let history = days.compactMap { day in
                day.rates[pair.quote].map { RatePoint(date: day.date, value: $0) }
            }
            guard let last = history.last else { return nil }
            let previous = history.dropLast().last?.value ?? last.value
            return RateQuote(
                pair: pair,
                source: .frankfurter,
                value: last.value,
                change: last.value - previous,
                history: history,
                date: last.date
            )
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

/// `api.coingecko.com`: the public API, which needs no key but limits how often it is asked.
public enum CoinGecko {
    private static let coins = ["BTC": "bitcoin", "ETH": "ethereum"]

    static func priceURL(pairs: [RatePair]) -> URL? {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")
        components?.queryItems = [
            URLQueryItem(name: "ids", value: Set(pairs.compactMap { coins[$0.base] }).sorted().joined(separator: ",")),
            URLQueryItem(
                name: "vs_currencies",
                value: Set(pairs.map { $0.quote.lowercased() }).sorted().joined(separator: ",")
            ),
            URLQueryItem(name: "include_24hr_change", value: "true"),
            URLQueryItem(name: "include_last_updated_at", value: "true"),
        ]
        return components?.url
    }

    static func chartURL(for pair: RatePair) -> URL? {
        guard let coin = coins[pair.base] else { return nil }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/\(coin)/market_chart")
        components?.queryItems = [
            URLQueryItem(name: "vs_currency", value: pair.quote.lowercased()),
            URLQueryItem(name: "days", value: "7"),
            URLQueryItem(name: "interval", value: "daily"),
        ]
        return components?.url
    }

    public static func quotes(from data: Data, pairs: [RatePair]) throws -> [RateQuote] {
        let response = try JSONDecoder().decode([String: [String: Double?]].self, from: data)
        return pairs.compactMap { pair in
            let currency = pair.quote.lowercased()
            // Fields the service has no value for arrive as `null`.
            guard let coin = coins[pair.base], let fields = response[coin]?.compactMapValues(\.self),
                  let value = fields[currency]
            else { return nil }
            let percent = fields["\(currency)_24h_change"] ?? 0
            let updated = fields["last_updated_at"] ?? 0
            return RateQuote(
                pair: pair,
                source: .coinGecko,
                value: value,
                change: value - value / (1 + percent / 100),
                history: [],
                date: Date(timeIntervalSince1970: updated)
            )
        }
    }

    public static func history(from data: Data) throws -> [RatePoint] {
        try JSONDecoder().decode(CoinGeckoChart.self, from: data).prices.compactMap { entry in
            guard entry.count == 2 else { return nil }
            return RatePoint(date: Date(timeIntervalSince1970: entry[0] / 1000), value: entry[1])
        }
    }
}

private struct CBRResponse: Decodable {
    let date: String
    let previousURL: String?
    let valute: [String: CBRCurrency]

    private enum CodingKeys: String, CodingKey {
        case date = "Date"
        case previousURL = "PreviousURL"
        case valute = "Valute"
    }
}

private struct CBRCurrency: Decodable {
    let nominal: Double
    let value: Double
    let previous: Double

    private enum CodingKeys: String, CodingKey {
        case nominal = "Nominal"
        case value = "Value"
        case previous = "Previous"
    }
}

private struct FrankfurterResponse: Decodable {
    let rates: [String: [String: Double]]
}

private struct CoinGeckoChart: Decodable {
    let prices: [[Double]]
}
