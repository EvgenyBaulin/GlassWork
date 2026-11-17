import Foundation

/// The readings of one sensor over a minute, an hour and a day, and its extremes since the app started.
public struct SensorTrack: Sendable {
    public private(set) var history = TieredHistory()
    public private(set) var minimum: Double
    public private(set) var maximum: Double

    init(first value: Double, at date: Date) {
        minimum = value
        maximum = value
        history.append(value, at: date)
    }

    mutating func add(_ value: Double, at date: Date) {
        history.append(value, at: date)
        minimum = min(minimum, value)
        maximum = max(maximum, value)
    }

    public func points(in range: TieredHistory.Range, now: Date = Date()) -> [History<Double>.Point] {
        history.points(in: range, now: now)
    }
}

/// Per-sensor histories (about 19 KB each) for the sensors the panel lists. The extremes live apart from the buffer,
/// so they cover the whole session and not only the points that are still kept.
public struct SensorTracker: Sendable {
    public private(set) var tracks: [String: SensorTrack] = [:]

    public init() {}

    public func track(for key: String) -> SensorTrack? {
        tracks[key]
    }

    /// Adds a sample. Sensors of groups that are not listed are not kept, and drop out when a group is hidden.
    /// A sensor missing from one sample keeps what it has.
    public mutating func apply(_ sample: SensorSample, groups: Set<SensorGroup>, at date: Date) {
        for reading in sample.readings {
            guard groups.contains(reading.group) else {
                tracks[reading.key] = nil
                continue
            }
            if tracks[reading.key] == nil {
                tracks[reading.key] = SensorTrack(first: reading.celsius, at: date)
            } else {
                tracks[reading.key]?.add(reading.celsius, at: date)
            }
        }
    }
}
