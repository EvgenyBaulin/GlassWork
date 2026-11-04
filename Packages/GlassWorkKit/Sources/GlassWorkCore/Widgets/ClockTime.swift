import Foundation

/// A wall-clock reading in one time zone, with the angles of analog hands.
public struct ClockTime: Sendable, Equatable {
    public let hour: Int
    public let minute: Int
    public let second: Int
    /// Calendar days from the reference zone: -1 yesterday, 0 same day, 1 tomorrow.
    public let dayOffset: Int
    /// Hours the zone is ahead of the reference zone, for "+3 h" captions.
    public let hoursFromReference: Double

    public init(date: Date, timeZone: TimeZone, reference: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
        second = parts.second ?? 0
        var home = Calendar(identifier: .gregorian)
        home.timeZone = reference
        let homeParts = home.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let here = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
        let there = utc.date(from: DateComponents(year: homeParts.year, month: homeParts.month, day: homeParts.day))
            ?? date
        dayOffset = Int((here.timeIntervalSince(there) / 86400).rounded())
        hoursFromReference = Double(timeZone.secondsFromGMT(for: date) - reference.secondsFromGMT(for: date)) / 3600
    }

    /// Degrees clockwise from 12 o'clock.
    public var hourAngle: Double {
        Double(hour % 12) * 30 + Double(minute) * 0.5
    }

    public var minuteAngle: Double {
        Double(minute) * 6 + Double(second) * 0.1
    }

    public var secondAngle: Double {
        Double(second) * 6
    }

    /// 06:00 to 18:00 counts as day, the way the world-clock faces are drawn.
    public var isDaytime: Bool {
        (6 ..< 18).contains(hour)
    }

    /// Share of the 24-hour day that has passed.
    public var dayShare: Double {
        (Double(hour) * 3600 + Double(minute) * 60 + Double(second)) / 86400
    }
}

public extension WorldCity {
    var zone: TimeZone? {
        TimeZone(identifier: timeZone)
    }
}
