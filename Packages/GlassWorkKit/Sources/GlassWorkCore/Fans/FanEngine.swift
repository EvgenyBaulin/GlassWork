import Foundation

/// One instruction for the helper: the only thing it can be asked to do to a fan.
public struct FanCommand: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        case auto, max
        case target(Double)
    }

    public var fan: Int
    public var action: Action

    public init(fan: Int, action: Action) {
        self.fan = fan
        self.action = action
    }
}

/// Why fans went back to the system.
public enum FanAutoReason: Sendable, Equatable {
    case sensorLost, helperLost, sleep
}

/// Something the user should be told about.
public enum FanNotice: Sendable, Equatable {
    case failsafeMax(celsius: Double, previous: FanMode)
    case returnedToAuto(FanAutoReason)
}

/// What the engine looks at on every step.
public struct FanEngineInput: Sendable {
    public var time: TimeInterval
    public var sample: SensorSample?
    public var isOnAC: Bool
    public var settings: FanSettings

    public init(time: TimeInterval, sample: SensorSample?, isOnAC: Bool, settings: FanSettings) {
        self.time = time
        self.sample = sample
        self.isOnAC = isOnAC
        self.settings = settings
    }
}

/// Decides what fans should do. Pure: time and readings come in, commands come out.
public struct FanEngine: Sendable {
    public static let failsafeCelsius = 95.0
    public static let wakeDelay = 10.0

    public private(set) var mode = FanMode.auto
    public private(set) var notice: FanNotice?
    /// Set between a wake and the moment the curve is applied again.
    public private(set) var resumeTime: TimeInterval?

    private var modeBeforeMax: FanMode?
    private var resumeAfterWake = false
    private var filter = FanTemperatureFilter()
    private var limiter = FanSlewLimiter()
    private var handOver = FanHandOver()
    /// Last instruction per fan. A fan listed here is out of the system's hands.
    private var sent: [Int: FanCommand.Action] = [:]

    public init() {}

    /// True while the helper has to be kept informed that the app is alive.
    public var isActive: Bool {
        mode != .auto || !sent.isEmpty
    }

    /// True while a curve has left the fans to the system because the Mac is cool.
    public var isWithSystem: Bool {
        mode == .curve && handOver.isWithSystem
    }

    /// True when a fan has been told what to do and the helper should still hold it.
    public var holdsFans: Bool {
        !sent.isEmpty
    }

    /// A choice made by the user. It always clears a pending notice or resume.
    public mutating func select(_ newMode: FanMode) {
        mode = newMode
        modeBeforeMax = nil
        resumeTime = nil
        resumeAfterWake = false
        notice = nil
        resetSmoothing()
    }

    /// The one-click Max: on, or back to whatever ran before it.
    public mutating func toggleMax() {
        if mode == .max {
            select(modeBeforeMax ?? .auto)
        } else {
            let previous = mode
            select(.max)
            modeBeforeMax = previous
        }
    }

    public mutating func dismissNotice() {
        notice = nil
    }

    public mutating func step(_ input: FanEngineInput) -> [FanCommand] {
        if let resumeTime, input.time >= resumeTime {
            self.resumeTime = nil
            mode = .curve
        }
        switch mode {
        case .auto:
            return release()
        case .max:
            return commandMax(fans: input.sample?.fans ?? [])
        case .curve, .custom:
            return runManaged(input)
        }
    }

    /// Fans go back to the system for the night. Only a curve comes back by itself.
    public mutating func willSleep() -> [FanCommand] {
        resumeAfterWake = mode == .curve
        let wasManaged = mode != .auto
        mode = .auto
        modeBeforeMax = nil
        resumeTime = nil
        if wasManaged, !resumeAfterWake {
            notice = .returnedToAuto(.sleep)
        }
        resetSmoothing()
        return release()
    }

    public mutating func didWake(at time: TimeInterval) {
        if resumeAfterWake {
            resumeTime = time + Self.wakeDelay
        }
        resumeAfterWake = false
    }

    /// The helper is gone and has restored Auto by itself, so there is nothing left to send.
    public mutating func helperLost() {
        let wasManaged = isActive
        mode = .auto
        modeBeforeMax = nil
        resumeTime = nil
        resumeAfterWake = false
        sent = [:]
        resetSmoothing()
        if wasManaged {
            notice = .returnedToAuto(.helperLost)
        }
    }

    private mutating func runManaged(_ input: FanEngineInput) -> [FanCommand] {
        guard let sample = input.sample, let cpu = sample.averageCPU else {
            return fallBack(.sensorLost)
        }
        if cpu > Self.failsafeCelsius {
            notice = .failsafeMax(celsius: cpu, previous: mode)
            modeBeforeMax = mode
            mode = .max
            resetSmoothing()
            return commandMax(fans: sample.fans)
        }
        let fans = sample.fans.filter(\.hasValidRange)
        let released = releaseFans(except: Set(fans.map(\.id)))
        let wanted: [Int: Double]
        if mode == .curve {
            guard let celsius = sample.celsius(for: input.settings.sensor) else {
                return fallBack(.sensorLost)
            }
            let steady = filter.filtered(celsius, at: input.time)
            let wasWithSystem = handOver.isWithSystem
            let threshold = input.settings.handOverThreshold
            if handOver.update(steady: steady, threshold: threshold, at: input.time) {
                limiter.reset()
                return released + release()
            }
            if wasWithSystem {
                // The system moved the fans meanwhile: the ramp starts from what they do now.
                limiter.reset()
            }
            wanted = Dictionary(uniqueKeysWithValues: fans.map { fan in
                let curve = input.settings.curve(forFan: fan.id, isOnAC: input.isOnAC)
                return (fan.id, curve.rpm(at: steady, in: fan.minimum ... fan.maximum))
            })
        } else {
            wanted = Dictionary(uniqueKeysWithValues: fans.map { fan in
                (fan.id, fan.clamped(input.settings.customTarget(forFan: fan.id)))
            })
        }
        // A stopped fan starts from its minimum: the SMC accepts nothing lower.
        let starts = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, $0.clamped($0.rpm)) })
        let targets = limiter.limited(wanted, starts: starts, at: input.time)
        return released + targets.keys.sorted().compactMap { fan in
            let action = FanCommand.Action.target((targets[fan] ?? 0).rounded())
            guard sent[fan] != action else { return nil }
            sent[fan] = action
            return FanCommand(fan: fan, action: action)
        }
    }

    private mutating func commandMax(fans: [FanReading]) -> [FanCommand] {
        // A fan already held counts even with unreadable limits: the helper reads its own, and left
        // out it would stay at a low target.
        Set(fans.filter(\.hasValidRange).map(\.id)).union(sent.keys).sorted().compactMap { fan in
            guard sent[fan] != .max else { return nil }
            sent[fan] = .max
            return FanCommand(fan: fan, action: .max)
        }
    }

    /// A fan that can no longer be steered goes back to the system, not stuck at its last target.
    private mutating func releaseFans(except kept: Set<Int>) -> [FanCommand] {
        sent.keys.filter { !kept.contains($0) }.sorted().map { fan in
            sent[fan] = nil
            return FanCommand(fan: fan, action: .auto)
        }
    }

    private mutating func fallBack(_ reason: FanAutoReason) -> [FanCommand] {
        mode = .auto
        modeBeforeMax = nil
        notice = .returnedToAuto(reason)
        resetSmoothing()
        return release()
    }

    private mutating func release() -> [FanCommand] {
        let commands = sent.keys.sorted().map { FanCommand(fan: $0, action: .auto) }
        sent = [:]
        return commands
    }

    private mutating func resetSmoothing() {
        filter.reset()
        limiter.reset()
        handOver.reset()
    }
}

public extension FanReading {
    /// False when the limits could not be read, in which case the fan stays with the system.
    var hasValidRange: Bool {
        maximum > 0 && maximum >= minimum
    }

    func clamped(_ rpm: Double) -> Double {
        Swift.min(Swift.max(rpm, minimum), maximum)
    }
}
