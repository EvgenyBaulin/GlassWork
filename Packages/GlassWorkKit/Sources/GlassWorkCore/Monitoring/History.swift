import Foundation

/// Fixed-capacity ring buffer of timestamped values kept in memory only.
public struct History<Value: Sendable>: Sendable {
    public struct Point: Sendable {
        public let date: Date
        public let value: Value

        public init(date: Date, value: Value) {
            self.date = date
            self.value = value
        }
    }

    public let capacity: Int
    private var storage: [Point] = []
    private var head = 0

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int {
        storage.count
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    public var latest: Point? {
        points.last
    }

    public mutating func append(_ value: Value, at date: Date) {
        let point = Point(date: date, value: value)
        if storage.count < capacity {
            storage.append(point)
        } else {
            storage[head] = point
            head = (head + 1) % capacity
        }
    }

    /// Points in chronological order.
    public var points: [Point] {
        Array(storage[head...] + storage[..<head])
    }

    public func points(since date: Date) -> [Point] {
        points.filter { $0.date >= date }
    }
}

extension History.Point: Codable where Value: Codable {}

extension History.Point: Equatable where Value: Equatable {}

/// Three resolutions of one metric: 1 minute, 1 hour and 24 hours.
public struct TieredHistory: Sendable {
    public enum Range: String, CaseIterable, Codable, Sendable {
        case minute, hour, day

        public var duration: TimeInterval {
            switch self {
            case .minute: 60
            case .hour: 3600
            case .day: 86400
            }
        }
    }

    private var fine = History<Double>(capacity: 120)
    private var medium = History<Double>(capacity: 360)
    private var coarse = History<Double>(capacity: 720)
    private var mediumBucket = Bucket(length: 10)
    private var coarseBucket = Bucket(length: 120)

    public init() {}

    public mutating func append(_ value: Double, at date: Date) {
        fine.append(value, at: date)
        if let average = mediumBucket.add(value, at: date) {
            medium.append(average, at: date)
        }
        if let average = coarseBucket.add(value, at: date) {
            coarse.append(average, at: date)
        }
    }

    public func points(in range: Range, now: Date = Date()) -> [History<Double>.Point] {
        let since = now.addingTimeInterval(-range.duration)
        switch range {
        case .minute: return fine.points(since: since)
        case .hour: return medium.points(since: since)
        case .day: return coarse.points(since: since)
        }
    }

    public var latest: Double? {
        fine.latest?.value
    }

    /// Averages values over a fixed time window.
    private struct Bucket: Sendable {
        let length: TimeInterval
        var start: Date?
        var sum = 0.0
        var count = 0.0

        init(length: TimeInterval) {
            self.length = length
        }

        mutating func add(_ value: Double, at date: Date) -> Double? {
            let origin = start ?? date
            start = origin
            sum += value
            count += 1
            guard date.timeIntervalSince(origin) >= length else { return nil }
            let average = sum / count
            start = date
            sum = 0
            count = 0
            return average
        }
    }
}
