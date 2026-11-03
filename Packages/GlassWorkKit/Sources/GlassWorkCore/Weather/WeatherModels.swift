import Foundation

/// A city from the geocoding service, or the Mac's own position.
public struct WeatherPlace: Codable, Sendable, Equatable, Hashable, Identifiable {
    /// Reserved for the Mac's own position; geocoding ids are positive.
    public static let currentLocationID = 0

    public var id: Int
    public var name: String
    public var country: String
    public var latitude: Double
    public var longitude: Double

    public init(id: Int, name: String, country: String, latitude: Double, longitude: Double) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isCurrentLocation: Bool {
        id == Self.currentLocationID
    }
}

public struct WeatherSettings: Codable, Sendable, Equatable {
    public var places: [WeatherPlace] = []
    /// Off until the user turns it on; macOS is not asked for the position before that.
    public var useCurrentLocation = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case places, useCurrentLocation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        places = try container.decodeIfPresent([WeatherPlace].self, forKey: .places) ?? []
        useCurrentLocation = try container.decodeIfPresent(Bool.self, forKey: .useCurrentLocation) ?? false
    }
}

/// Weather in plain terms, grouped from WMO codes.
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, freezingRain, snow, showers, snowShowers
    case thunderstorm, unknown

    private static let codes: [Int: WeatherCondition] = [
        0: .clear, 1: .clear, 2: .partlyCloudy, 3: .cloudy, 45: .fog, 48: .fog,
        51: .drizzle, 53: .drizzle, 55: .drizzle, 56: .freezingRain, 57: .freezingRain,
        61: .rain, 63: .rain, 65: .rain, 66: .freezingRain, 67: .freezingRain,
        71: .snow, 73: .snow, 75: .snow, 77: .snow, 80: .showers, 81: .showers, 82: .showers,
        85: .snowShowers, 86: .snowShowers, 95: .thunderstorm, 96: .thunderstorm, 99: .thunderstorm,
    ]

    public init(wmoCode: Int) {
        self = Self.codes[wmoCode] ?? .unknown
    }

    public func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max" : "moon.stars"
        case .partlyCloudy: isDay ? "cloud.sun" : "cloud.moon"
        case .cloudy: "cloud"
        case .fog: "cloud.fog"
        case .drizzle: "cloud.drizzle"
        case .rain, .showers: "cloud.rain"
        case .freezingRain: "cloud.sleet"
        case .snow, .snowShowers: "cloud.snow"
        case .thunderstorm: "cloud.bolt.rain"
        case .unknown: "cloud"
        }
    }
}

public enum UVLevel: Sendable, Equatable {
    case low, moderate, high, veryHigh, extreme

    public init(index: Double) {
        switch index.rounded() {
        case ..<3: self = .low
        case ..<6: self = .moderate
        case ..<8: self = .high
        case ..<11: self = .veryHigh
        default: self = .extreme
        }
    }
}

public struct CurrentWeather: Codable, Sendable, Equatable {
    public var temperature: Double
    public var feelsLike: Double
    public var humidity: Double
    public var windSpeed: Double
    public var uvIndex: Double
    public var condition: WeatherCondition
    public var isDay: Bool
}

public struct HourForecast: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var temperature: Double
    public var condition: WeatherCondition
    public var isDay: Bool

    public var id: Date {
        date
    }
}

public struct DayForecast: Codable, Sendable, Equatable, Identifiable {
    public var date: Date
    public var low: Double
    public var high: Double
    public var condition: WeatherCondition

    public var id: Date {
        date
    }
}

/// Everything shown for one place. Times are real moments; `timeZone` says how the place reads them.
public struct WeatherReport: Codable, Sendable, Equatable, Identifiable {
    public var place: WeatherPlace
    public var timeZone: String
    public var fetchedAt: Date
    public var current: CurrentWeather
    public var hours: [HourForecast]
    public var days: [DayForecast]

    public var id: Int {
        place.id
    }

    public var zone: TimeZone {
        TimeZone(identifier: timeZone) ?? .current
    }

    /// Lowest and highest temperature of the whole forecast, the shared scale of the range bars.
    public var temperatureRange: ClosedRange<Double>? {
        guard let low = days.map(\.low).min(), let high = days.map(\.high).max(), low < high else { return nil }
        return low ... high
    }
}

/// What the app keeps for the offline state, and what a widget can read later.
public struct WeatherSnapshot: Codable, Sendable, Equatable {
    public static let key = "weather"

    public var reports: [WeatherReport] = []

    public init(reports: [WeatherReport] = []) {
        self.reports = reports
    }
}
