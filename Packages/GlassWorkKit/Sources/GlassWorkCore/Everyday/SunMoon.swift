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

    private static func moment(_ julian: Double) -> Date {
        Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86400)
    }
}
