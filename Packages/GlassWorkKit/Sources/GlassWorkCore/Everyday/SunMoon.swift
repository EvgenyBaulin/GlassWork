import Foundation

public struct SunTimes: Sendable, Equatable {
    public var sunrise: Date?
    public var sunset: Date?

    public var daylight: TimeInterval? {
        guard let sunrise, let sunset else { return nil }
        return sunset.timeIntervalSince(sunrise)
    }
}

public enum MoonPhase: String, CaseIterable, Sendable {
    case new, waxingCrescent, firstQuarter, waxingGibbous, full, waningGibbous, lastQuarter, waningCrescent

    public var symbol: String {
        switch self {
        case .new: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .full: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }
}

public enum SunEvent: Sendable, Equatable {
    case sunrise, sunset
}

/// Which event the Sun and Moon item counts down to.
public enum SunShows: String, Sendable, CaseIterable {
    case next, sunrise, sunset
}

public struct NextSunEvent: Sendable, Equatable {
    public let event: SunEvent
    public let date: Date
}

/// The place the sun is worked out for. Only places the user gave to Weather count: there is no built-in city,
/// and nothing here asks macOS for the position.
public enum SunLocation {
    public static func place(in places: [WeatherPlace], chosen: Int?) -> WeatherPlace? {
        places.first { $0.id == chosen } ?? places.first
    }
}

/// Sun and moon positions computed locally, so this module needs no network.
public enum Astronomy {
    private static let synodicMonth = 29.530588853
    /// 2000-01-06 18:14 UTC, a known new moon.
    private static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)

    /// Share of the lunar cycle: 0 is new moon, 0.5 is full.
    public static func moonAge(at date: Date) -> Double {
        let days = date.timeIntervalSince(knownNewMoon) / 86400
        let cycles = days / synodicMonth
        return cycles - floor(cycles)
    }

    public static func moonPhase(at date: Date) -> MoonPhase {
        let index = Int((moonAge(at: date) * 8).rounded()) % 8
        return MoonPhase.allCases[index]
    }

    /// Lit share of the moon's disc.
    public static func moonIllumination(at date: Date) -> Double {
        (1 - cos(moonAge(at: date) * 2 * .pi)) / 2
    }

    /// Sunrise equation. Polar day and night return nil times.
    public static func sunTimes(on date: Date, latitude: Double, longitude: Double) -> SunTimes {
        let julian = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        // East longitudes reach solar noon earlier, so they are subtracted.
        let cycle = (julian - 2_451_545 - 0.0009 + longitude / 360).rounded()
        let mean = 2_451_545 + 0.0009 - longitude / 360 + cycle
        let anomaly = (357.5291 + 0.98560028 * (mean - 2_451_545)).truncatingRemainder(dividingBy: 360)
        let radians = anomaly * .pi / 180
        let center = 1.9148 * sin(radians) + 0.02 * sin(2 * radians) + 0.0003 * sin(3 * radians)
        let ecliptic = ((anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)) * .pi / 180
        let transit = mean + 0.0053 * sin(radians) - 0.0069 * sin(2 * ecliptic)
        let declination = asin(sin(ecliptic) * sin(23.44 * .pi / 180))
        let phi = latitude * .pi / 180
        let hour = (sin(-0.833 * .pi / 180) - sin(phi) * sin(declination)) / (cos(phi) * cos(declination))
        guard abs(hour) <= 1 else { return SunTimes(sunrise: nil, sunset: nil) }
        let offset = acos(hour) / (2 * .pi)
        return SunTimes(sunrise: moment(transit - offset), sunset: moment(transit + offset))
    }

    /// The next sunrise or sunset. Looks past today, since after sunset the next event is tomorrow's.
    /// Nil only where the sun neither rises nor sets for days, as in a polar night.
    public static func nextEvent(
        _ shows: SunShows,
        after date: Date,
        latitude: Double,
        longitude: Double
    ) -> NextSunEvent? {
        for offset in 0 ... 2 {
            let day = date.addingTimeInterval(Double(offset) * 86400)
            let times = sunTimes(on: day, latitude: latitude, longitude: longitude)
            let sunrise = shows == .sunset ? nil : times.sunrise.map { NextSunEvent(event: .sunrise, date: $0) }
            let sunset = shows == .sunrise ? nil : times.sunset.map { NextSunEvent(event: .sunset, date: $0) }
            let upcoming = [sunrise, sunset].compactMap(\.self).filter { $0.date > date }
            if let next = upcoming.min(by: { $0.date < $1.date }) {
                return next
            }
        }
        return nil
    }

    private static func moment(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86400)
    }
}
