import Foundation

/// Steadies a temperature before it reaches a curve, so fans do not chase every reading.
public struct FanTemperatureFilter: Sendable {
    public static let averageWindow = 5.0
    public static let hysteresis = 3.0

    private var samples: [(time: TimeInterval, celsius: Double)] = []
    private var held: Double?

    public init() {}

    /// Mean of the last five seconds, then hysteresis.
    ///
    /// Heating is followed at once. Cooling is ignored until the temperature has fallen by the
    /// hysteresis, then trails it by that amount, so a cooling fan never jumps.
    public mutating func filtered(_ celsius: Double, at time: TimeInterval) -> Double {
        samples.append((time, celsius))
        samples.removeAll { time - $0.time > Self.averageWindow }
        let mean = samples.map(\.celsius).reduce(0, +) / Double(samples.count)
        guard let current = held else {
            held = mean
            return mean
        }
        let next = mean > current ? mean : Swift.min(current, mean + Self.hysteresis)
        held = next
        return next
    }

    public mutating func reset() {
        samples = []
        held = nil
    }
}

/// Decides when a curve leaves the fans to the system, because the Mac is cool enough for them to stop.
///
/// Giving fans back and taking them again is a write to the SMC, so it must not happen on every small change: the
/// fans return only `band` above the threshold, and once back they stay at least `minimumHold`.
public struct FanHandOver: Sendable {
    public static let band = 3.0
    public static let minimumHold = 60.0

    public private(set) var isWithSystem = false
    private var takenBackAt: TimeInterval?

    public init() {}

    /// `threshold` nil means the option is off. Returns true when the fans should be with the system now.
    public mutating func update(steady celsius: Double, threshold: Double?, at time: TimeInterval) -> Bool {
        guard let threshold else {
            takeBack(at: time)
            return false
        }
        if isWithSystem {
            if celsius >= threshold + Self.band {
                takeBack(at: time)
            }
        } else if celsius < threshold, hasHeld(at: time) {
            isWithSystem = true
        }
        return isWithSystem
    }

    private func hasHeld(at time: TimeInterval) -> Bool {
        takenBackAt.map { time - $0 >= Self.minimumHold } ?? true
    }

    private mutating func takeBack(at time: TimeInterval) {
        if isWithSystem {
            takenBackAt = time
        }
        isWithSystem = false
    }

    public mutating func reset() {
        isWithSystem = false
        takenBackAt = nil
    }
}

/// Limits how fast each fan's target may change.
public struct FanSlewLimiter: Sendable {
    public static let maximumRate = 300.0

    private var targets: [Int: Double] = [:]
    private var lastTime: TimeInterval?

    public init() {}

    /// Moves every fan towards its wanted speed. `starts` gives the speed a new fan begins from.
    public mutating func limited(
        _ wanted: [Int: Double],
        starts: [Int: Double],
        at time: TimeInterval
    ) -> [Int: Double] {
        let elapsed = lastTime.map { Swift.max(time - $0, 0) } ?? 0
        lastTime = time
        let step = Self.maximumRate * elapsed
        var result: [Int: Double] = [:]
        for (fan, target) in wanted {
            let current = targets[fan] ?? starts[fan] ?? target
            result[fan] = current + Swift.min(Swift.max(target - current, -step), step)
        }
        targets = result
        return result
    }

    public mutating func reset() {
        targets = [:]
        lastTime = nil
    }
}
