import Foundation

/// Open-Meteo requests and parsers. No key is needed.
public enum OpenMeteo {
    /// Hours kept per report: enough for today's strip without storing the whole week.
    private static let hourLimit = 24

    static func forecastURL(for place: WeatherPlace) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,"
                    + "weather_code,is_day,uv_index"
            ),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
        ]
        return components?.url
    }

    static func searchURL(for query: String, language: String) -> URL? {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "format", value: "json"),
        ]
        return components?.url
    }

    /// An empty result has no `results` key at all.
    public static func places(from data: Data) throws -> [WeatherPlace] {
        let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
        return (response.results ?? []).map {
            WeatherPlace(
                id: $0.id,
                name: $0.name,
                country: $0.country ?? "",
                latitude: $0.latitude,
                longitude: $0.longitude
            )
        }
    }

    /// Reads a forecast. Past hours of today are dropped, so the strip starts at `now`.
    public static func report(from data: Data, place: WeatherPlace, now: Date) throws -> WeatherReport {
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        let current = response.current
        return WeatherReport(
            place: place,
            timeZone: response.timezone,
            fetchedAt: now,
            current: CurrentWeather(
                temperature: current.temperature2m,
                feelsLike: current.apparentTemperature,
                humidity: current.relativeHumidity2m,
                windSpeed: current.windSpeed10m,
                uvIndex: current.uvIndex ?? 0,
                condition: WeatherCondition(wmoCode: current.weatherCode),
                isDay: current.isDay == 1
            ),
            hours: hours(response, from: now),
            days: days(response)
        )
    }

    /// Missing values arrive as `null`. Only that hour or day is skipped, not the whole forecast.
    private static func hours(_ response: ForecastResponse, from now: Date) -> [HourForecast] {
        let hourly = response.hourly
        let reader = LocalTimeReader(offset: response.utcOffsetSeconds, format: "yyyy-MM-dd'T'HH:mm")
        let forecasts = hourly.time.indices.compactMap { index -> HourForecast? in
            guard let date = reader.date(hourly.time[index]),
                  let temperature = hourly.temperature2m.value(at: index),
                  let code = hourly.weatherCode.value(at: index)
            else { return nil }
            return HourForecast(
                date: date,
                temperature: temperature,
                condition: WeatherCondition(wmoCode: code),
                isDay: hourly.isDay.value(at: index) != 0
            )
        }
        // The hour that is under way stays: its entry is stamped at the start of the hour.
        return Array(forecasts.filter { $0.date.addingTimeInterval(3600) > now }.prefix(hourLimit))
    }

    private static func days(_ response: ForecastResponse) -> [DayForecast] {
        let daily = response.daily
        let reader = LocalTimeReader(offset: response.utcOffsetSeconds, format: "yyyy-MM-dd")
        return daily.time.indices.compactMap { index in
            guard let date = reader.date(daily.time[index]),
                  let low = daily.temperature2mMin.value(at: index),
                  let high = daily.temperature2mMax.value(at: index),
                  let code = daily.weatherCode.value(at: index)
            else { return nil }
            return DayForecast(date: date, low: low, high: high, condition: WeatherCondition(wmoCode: code))
        }
    }
}

private extension Array {
    /// The value at a position, or nil when it is past the end or `null` in the response.
    func value<Wrapped>(at index: Int) -> Wrapped? where Element == Wrapped? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Open-Meteo sends local wall-clock text plus one offset for the whole response.
private struct LocalTimeReader {
    private let formatter: DateFormatter

    init(offset: Int, format: String) {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: offset)
        formatter.dateFormat = format
    }

    func date(_ text: String) -> Date? {
        formatter.date(from: text)
    }
}

private struct GeocodingResponse: Decodable {
    let results: [GeocodingResult]?
}

private struct GeocodingResult: Decodable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
}

private struct ForecastResponse: Decodable {
    let utcOffsetSeconds: Int
    let timezone: String
    let current: ForecastCurrent
    let hourly: ForecastHourly
    let daily: ForecastDaily

    private enum CodingKeys: String, CodingKey {
        case utcOffsetSeconds = "utc_offset_seconds"
        case timezone, current, hourly, daily
    }
}

private struct ForecastCurrent: Decodable {
    let temperature2m: Double
    let apparentTemperature: Double
    let relativeHumidity2m: Double
    let windSpeed10m: Double
    let weatherCode: Int
    let isDay: Int
    let uvIndex: Double?

    private enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case relativeHumidity2m = "relative_humidity_2m"
        case windSpeed10m = "wind_speed_10m"
        case weatherCode = "weather_code"
        case isDay = "is_day"
        case uvIndex = "uv_index"
    }
}

private struct ForecastHourly: Decodable {
    let time: [String]
    let temperature2m: [Double?]
    let weatherCode: [Int?]
    let isDay: [Int?]

    private enum CodingKeys: String, CodingKey {
        case time
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
        case isDay = "is_day"
    }
}

private struct ForecastDaily: Decodable {
    let time: [String]
    let weatherCode: [Int?]
    let temperature2mMax: [Double?]
    let temperature2mMin: [Double?]

    private enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
    }
}
