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
    private static let mediumStep: TimeInterval = 10
    private var mediumBucket = Bucket(length: mediumStep)
    private var coarseBucket = Bucket(length: 120)
    /// When the first value arrived, which is the app's start for a metric that is always read.
    public private(set) var firstDate: Date?

    public init() {}

    public mutating func append(_ value: Double, at date: Date) {
        if firstDate == nil {
            firstDate = date
        }
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

    /// True when the range reaches back past the first value, so the left of the chart is empty
    /// because the app was not running yet.
    public func reachesBeforeStart(_ range: Range, now: Date = Date()) -> Bool {
        guard let firstDate else { return false }
        return now.addingTimeInterval(-range.duration) < firstDate
    }

    /// The latest `span` seconds as plain values for a menu bar graph, at most `maxPoints` of them.
    /// Up to a minute reads the fine tier; longer reads the ten-second tier, averaged down when it has more points.
    public func graph(span: TimeInterval, maxPoints: Int, now: Date = Date()) -> [Double] {
        let since = now.addingTimeInterval(-span)
        if span <= Range.minute.duration {
            return Array(fine.points(since: since).suffix(maxPoints).map(\.value))
        }
        let values = medium.points(since: since).map(\.value)
        // A span that holds no more than `maxPoints` ten-second values only needs its newest ones: the point on
        // the very edge of the window must not make it look like one more than fits and halve the detail.
        if Int(span / Self.mediumStep) <= maxPoints {
            return Array(values.suffix(maxPoints))
        }
        return Self.thinned(values, to: maxPoints)
    }

    /// Averages neighbours so that no more than `limit` values remain.
    static func thinned(_ values: [Double], to limit: Int) -> [Double] {
        guard limit > 0, values.count > limit else { return values }
        let size = (values.count + limit - 1) / limit
        return stride(from: 0, to: values.count, by: size).map { start in
            let group = values[start ..< min(start + size, values.count)]
            return group.reduce(0, +) / Double(group.count)
        }
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

/// Lowest, average and highest value of the points a chart shows.
public struct RangeStats: Sendable, Equatable {
    public let minimum: Double
    public let average: Double
    public let maximum: Double

    /// Nil when there is nothing to summarize.
    public init?(_ points: [History<Double>.Point]) {
        guard let first = points.first else { return nil }
        var low = first.value
        var high = first.value
        var sum = 0.0
        for point in points {
            low = min(low, point.value)
            high = max(high, point.value)
            sum += point.value
        }
        minimum = low
        maximum = high
        average = sum / Double(points.count)
    }
}
