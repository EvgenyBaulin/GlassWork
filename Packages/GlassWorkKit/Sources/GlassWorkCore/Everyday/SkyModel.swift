import Foundation

public enum SkyPhase: String, Sendable, Equatable {
    case night, dawn, day, dusk
}

/// Where the sun stands over one place at one moment. Computed locally, no network.
public struct SkyState: Sendable, Equatable {
    /// Half an hour either side of sunrise and sunset counts as dawn and dusk.
    public static let twilight: TimeInterval = 1800

    public let sun: SunTimes
    public let phase: SkyPhase
    /// 0 at sunrise, 1 at sunset; nil at night.
    public let dayProgress: Double?
    /// 0 at sunset, 1 at the next sunrise; nil by day.
    public let nightProgress: Double?
    /// The next sunrise or sunset after the date, and which one it is.
    public let next: (date: Date, isSunrise: Bool)?

    public init(date: Date, latitude: Double, longitude: Double, calendar: Calendar = .current) {
        let today = Astronomy.sunTimes(on: date, latitude: latitude, longitude: longitude)
        sun = today
        guard let sunrise = today.sunrise, let sunset = today.sunset else {
            // Polar day or night: the summer half of the year is bright, the winter half dark.
            let month = calendar.component(.month, from: date)
            let isSummer = (latitude >= 0) == (4 ... 9).contains(month)
            phase = isSummer ? .day : .night
            dayProgress = isSummer ? 0.5 : nil
            nightProgress = isSummer ? nil : 0.5
            next = nil
            return
        }
        let twilight = Self.twilight
        if date < sunrise - twilight || date >= sunset + twilight {
            phase = .night
        } else if date < sunrise + twilight {
            phase = .dawn
        } else if date >= sunset - twilight {
            phase = .dusk
        } else {
            phase = .day
        }
        if date >= sunrise, date < sunset {
            dayProgress = date.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
        } else {
            dayProgress = nil
        }
        if date < sunrise {
            next = (sunrise, true)
            nightProgress = Self.share(of: date, from: sunset.addingTimeInterval(-86400), to: sunrise)
        } else if date < sunset {
            next = (sunset, false)
            nightProgress = nil
        } else {
            let tomorrow = Astronomy.sunTimes(
                on: date.addingTimeInterval(86400),
                latitude: latitude,
                longitude: longitude
            )
            next = tomorrow.sunrise.map { ($0, true) }
            nightProgress = tomorrow.sunrise.map { Self.share(of: date, from: sunset, to: $0) } ?? 0.5
        }
    }

    private static func share(of date: Date, from start: Date, to end: Date) -> Double {
        min(max(date.timeIntervalSince(start) / max(end.timeIntervalSince(start), 1), 0), 1)
    }

    public static func == (lhs: SkyState, rhs: SkyState) -> Bool {
        lhs.sun == rhs.sun && lhs.phase == rhs.phase && lhs.dayProgress == rhs.dayProgress
            && lhs.nightProgress == rhs.nightProgress
            && lhs.next?.date == rhs.next?.date && lhs.next?.isSunrise == rhs.next?.isSunrise
    }
}

/// How long the sun is up on one day.
public struct DaylightDay: Sendable, Equatable {
    public let date: Date
    public let seconds: TimeInterval
}

public extension Astronomy {
    /// Daylight length for each of `days` days from `start`, one per `step` days. Polar days count as 24 h or 0.
    static func daylight(
        from start: Date,
        days: Int,
        step: Int = 1,
        latitude: Double,
        longitude: Double,
        calendar: Calendar = .current
    ) -> [DaylightDay] {
        stride(from: 0, to: days, by: step).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: start)),
                  let noon = calendar.date(byAdding: .hour, value: 12, to: day)
            else { return nil }
            let times = sunTimes(on: noon, latitude: latitude, longitude: longitude)
            if let length = times.daylight {
                return DaylightDay(date: day, seconds: length)
            }
            let isSummer = (latitude >= 0) == (4 ... 9).contains(calendar.component(.month, from: day))
            return DaylightDay(date: day, seconds: isSummer ? 86400 : 0)
        }
    }
}
