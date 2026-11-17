import Foundation

/// The last readings of one sensor and its extremes since the app started.
public struct SensorTrack: Sendable {
    public private(set) var history: History<Double>
    public private(set) var minimum: Double
    public private(set) var maximum: Double

    init(capacity: Int, first value: Double, at date: Date) {
        history = History<Double>(capacity: capacity)
        minimum = value
        maximum = value
        history.append(value, at: date)
    }

    mutating func add(_ value: Double, at date: Date) {
        history.append(value, at: date)
        minimum = min(minimum, value)
        maximum = max(maximum, value)
    }

    public var points: [History<Double>.Point] {
        history.points
    }
}

/// Per-sensor ring buffers for the sensors the panel lists. The extremes live apart from the buffer,
/// so they cover the whole session and not only the points that are still kept.
public struct SensorTracker: Sendable {
    /// About 2.4 KB per sensor: a sensor that was read every 10 s is kept for 25 minutes.
    public static let capacity = 150

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
                tracks[reading.key] = SensorTrack(capacity: Self.capacity, first: reading.celsius, at: date)
            } else {
                tracks[reading.key]?.add(reading.celsius, at: date)
            }
        }
    }
}
