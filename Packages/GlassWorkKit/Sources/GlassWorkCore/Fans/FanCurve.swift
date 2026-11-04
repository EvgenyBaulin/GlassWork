import Foundation

/// Fan speed as a function of temperature.
///
/// Speed is a percentage of each fan's own SMC range, so one curve fits fans with different limits.
/// Every value of this type is valid: temperatures rise by at least `minimumGap`, speed never falls.
public struct FanCurve: Sendable, Equatable {
    public struct Point: Codable, Sendable, Equatable {
        public var celsius: Double
        public var percent: Double

        public init(celsius: Double, percent: Double) {
            self.celsius = celsius
            self.percent = percent
        }
    }

    public static let pointLimit = 2 ... 8
    public static let minimumGap = 1.0
    public static let temperatureRange = 30.0 ... 100.0
    public static let percentRange = 0.0 ... 100.0

    public private(set) var points: [Point]

    /// Repairs whatever it is given, because points also come from hand-edited settings.
    public init(points: [Point]) {
        self.points = Self.sanitized(points) ?? FanPreset.balancedPoints
    }

    /// Speed at a temperature. Flat outside the first and last points.
    public func percent(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if celsius <= first.celsius {
            return first.percent
        }
        if celsius >= last.celsius {
            return last.percent
        }
        let upperIndex = points.firstIndex { $0.celsius >= celsius } ?? points.count - 1
        let lower = points[upperIndex - 1]
        let upper = points[upperIndex]
        let position = (celsius - lower.celsius) / (upper.celsius - lower.celsius)
        return lower.percent + (upper.percent - lower.percent) * position
    }

    /// Speed for one fan, always inside its range.
    public func rpm(at celsius: Double, in range: ClosedRange<Double>) -> Double {
        Self.rpm(percent: percent(at: celsius), in: range)
    }

    public static func rpm(percent: Double, in range: ClosedRange<Double>) -> Double {
        let share = min(max(percent, percentRange.lowerBound), percentRange.upperBound) / 100
        return range.lowerBound + (range.upperBound - range.lowerBound) * share
    }

    /// Where a point may go: it stops at its neighbours and never swaps with them.
    public func allowedArea(of index: Int) -> (celsius: ClosedRange<Double>, percent: ClosedRange<Double>)? {
        guard points.indices.contains(index) else { return nil }
        let previous = index > 0 ? points[index - 1] : nil
        let next = index < points.count - 1 ? points[index + 1] : nil
        let coldest = previous.map { $0.celsius + Self.minimumGap } ?? Self.temperatureRange.lowerBound
        let hottest = next.map { $0.celsius - Self.minimumGap } ?? Self.temperatureRange.upperBound
        let slowest = previous?.percent ?? Self.percentRange.lowerBound
        let fastest = next?.percent ?? Self.percentRange.upperBound
        return (coldest ... hottest, slowest ... fastest)
    }

    /// The curve with one point moved as far towards `target` as its neighbours allow.
    public func moving(_ index: Int, to target: Point) -> FanCurve {
        guard let area = allowedArea(of: index), target.celsius.isFinite, target.percent.isFinite else { return self }
        var copy = self
        copy.points[index] = Point(
            celsius: min(max(target.celsius, area.celsius.lowerBound), area.celsius.upperBound),
            percent: min(max(target.percent, area.percent.lowerBound), area.percent.upperBound)
        )
        return copy
    }

    /// The curve with a new point, or nil at the point limit or when there is no room for it.
    public func inserting(_ point: Point) -> FanCurve? {
        guard points.count < Self.pointLimit.upperBound,
              point.celsius.isFinite, point.percent.isFinite,
              Self.temperatureRange.contains(point.celsius),
              points.allSatisfy({ abs($0.celsius - point.celsius) >= Self.minimumGap })
        else { return nil }
        let index = points.firstIndex { $0.celsius > point.celsius } ?? points.count
        let slowest = index > 0 ? points[index - 1].percent : Self.percentRange.lowerBound
        let fastest = index < points.count ? points[index].percent : Self.percentRange.upperBound
        var copy = self
        copy.points.insert(
            Point(celsius: point.celsius, percent: min(max(point.percent, slowest), fastest)),
            at: index
        )
        return copy
    }

    /// The curve without a point, or nil when only the minimum is left.
    public func removing(_ index: Int) -> FanCurve? {
        guard points.count > Self.pointLimit.lowerBound, points.indices.contains(index) else { return nil }
        var copy = self
        copy.points.remove(at: index)
        return copy
    }

    private static func sanitized(_ raw: [Point]) -> [Point]? {
        let limited = raw
            .filter { $0.celsius.isFinite && $0.percent.isFinite }
            .map { point in
                Point(
                    celsius: min(max(point.celsius, temperatureRange.lowerBound), temperatureRange.upperBound),
                    percent: min(max(point.percent, percentRange.lowerBound), percentRange.upperBound)
                )
            }
            .sorted { $0.celsius < $1.celsius }
        var result: [Point] = []
        for point in limited {
            if let last = result.last {
                guard point.celsius - last.celsius >= minimumGap else { continue }
                result.append(Point(celsius: point.celsius, percent: max(point.percent, last.percent)))
            } else {
                result.append(point)
            }
        }
        let kept = Array(result.prefix(pointLimit.upperBound))
        return kept.count >= pointLimit.lowerBound ? kept : nil
    }
}

extension FanCurve: Codable {
    public init(from decoder: Decoder) throws {
        try self.init(points: decoder.singleValueContainer().decode([Point].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(points)
    }
}

/// A named curve. The three built-in ones cannot be renamed or deleted.
public struct FanPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var curve: FanCurve

    public init(id: String, name: String, curve: FanCurve) {
        self.id = id
        self.name = name
        self.curve = curve
    }

    public var isBuiltIn: Bool {
        Self.builtIn.contains { $0.id == id }
    }

    static let balancedPoints: [FanCurve.Point] = [
        .init(celsius: 30, percent: 0),
        .init(celsius: 45, percent: 15),
        .init(celsius: 60, percent: 44),
        .init(celsius: 75, percent: 70),
        .init(celsius: 90, percent: 100),
    ]

    public static let silent = FanPreset(id: "silent", name: "Silent", curve: FanCurve(points: [
        .init(celsius: 30, percent: 0),
        .init(celsius: 50, percent: 5),
        .init(celsius: 65, percent: 25),
        .init(celsius: 80, percent: 60),
        .init(celsius: 92, percent: 100),
    ]))

    public static let balanced = FanPreset(id: "balanced", name: "Balanced", curve: FanCurve(points: balancedPoints))

    public static let performance = FanPreset(id: "performance", name: "Performance", curve: FanCurve(points: [
        .init(celsius: 30, percent: 15),
        .init(celsius: 45, percent: 40),
        .init(celsius: 60, percent: 70),
        .init(celsius: 75, percent: 90),
        .init(celsius: 85, percent: 100),
    ]))

    public static let builtIn = [silent, balanced, performance]
}
