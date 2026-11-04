import Foundation

/// What the helper needs from the SMC. The real writer exists only in the helper's own target,
/// so neither the app nor the tests can reach a write.
public protocol FanSMCAccess: AnyObject {
    func read(_ key: String) -> SMCClient.Value?
    /// True when the SMC accepted the bytes.
    func write(_ key: String, bytes: [UInt8]) -> Bool
}

/// Carries out fan commands. Not thread-safe: the daemon calls it from one serial queue.
///
/// It trusts nothing it is sent. Fan numbers and speeds are checked against the SMC's own limits.
public final class FanHelperService {
    public enum Mode {
        static let automatic = 0.0
        static let manual = 1.0
        /// What Apple silicon reports under system control. Only here can a fan stop: mode 0 holds it at minimum.
        static let system = 3.0
    }

    /// Waits between attempts while macOS hands over control of the fans.
    public struct Timing: Sendable {
        public var unlockDelay = 3.0
        public var retryDelay = 0.25
        /// macOS can take a long time to hand fans over, so this waits about 30 s.
        public var unlockAttempts = 120
        public var restoreAttempts = 20

        public init() {}
    }

    /// The only keys the helper may ever write: a fan's mode and target, and the unlock switch.
    public static func isWritable(_ key: String) -> Bool {
        key.wholeMatch(of: /Ftst|F[0-9](Md|md|Tg)/) != nil
    }

    private let smc: FanSMCAccess
    private let timing: Timing
    private let pause: (TimeInterval) -> Void
    /// Once the key has been seen, an unreadable `Ftst` is a failed read, not a Mac without one.
    private var hasTestKey: Bool

    public init(
        smc: FanSMCAccess,
        timing: Timing = Timing(),
        pause: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.smc = smc
        self.timing = timing
        self.pause = pause
        hasTestKey = smc.read("Ftst") != nil
    }

    /// Nil when the SMC did not answer, which must not pass for a Mac with nothing to restore.
    private var fanCount: Int? {
        smc.read("FNum")?.number.map { Int($0) }
    }

    /// The key's case differs between Mac models.
    private func modeKey(_ fan: Int) -> String? {
        ["F\(fan)Md", "F\(fan)md"].first { smc.read($0) != nil }
    }

    public var hasManualFans: Bool {
        (0 ..< (fanCount ?? 0)).contains { fan in
            modeKey(fan).flatMap { smc.read($0)?.number }.map(FanReading.isManualMode) ?? false
        }
    }

    /// Returns true when the fan now does what was asked.
    @discardableResult
    public func execute(_ command: FanCommand) -> Bool {
        guard (0 ..< (fanCount ?? 0)).contains(command.fan) else { return false }
        switch command.action {
        case .auto:
            return restoreFan(command.fan) && releaseTestModeIfIdle()
        case .max:
            guard let range = limits(command.fan) else { return false }
            return drive(command.fan, rpm: range.upperBound)
        case let .target(rpm):
            guard rpm.isFinite, let range = limits(command.fan) else { return false }
            return drive(command.fan, rpm: min(max(rpm, range.lowerBound), range.upperBound))
        }
    }

    /// Hands every fan back to the system. Writes nothing when no fan is ours.
    @discardableResult
    public func restoreAuto() -> Bool {
        guard let fanCount else { return false }
        var succeeded = true
        for fan in 0 ..< fanCount where !restoreFan(fan) {
            succeeded = false
        }
        return releaseTestModeIfIdle() && succeeded
    }

    private func limits(_ fan: Int) -> ClosedRange<Double>? {
        guard let minimum = smc.read("F\(fan)Mn")?.number,
              let maximum = smc.read("F\(fan)Mx")?.number,
              maximum > 0, maximum >= minimum
        else { return nil }
        return minimum ... maximum
    }

    private func drive(_ fan: Int, rpm: Double) -> Bool {
        guard takeControl(of: fan), let target = smc.read("F\(fan)Tg"), let bytes = target.encoded(rpm) else {
            return false
        }
        return smc.write("F\(fan)Tg", bytes: bytes)
    }

    /// Newer Macs accept the mode directly. Others refuse it until `Ftst` is set and macOS lets go.
    private func takeControl(of fan: Int) -> Bool {
        guard let key = modeKey(fan), let mode = smc.read(key) else { return false }
        if mode.number.map(FanReading.isManualMode) == true {
            return true
        }
        guard let manual = mode.encoded(Mode.manual) else { return false }
        if smc.write(key, bytes: manual) {
            return true
        }
        guard let test = smc.read("Ftst"), let unlock = test.encoded(1), smc.write("Ftst", bytes: unlock) else {
            return false
        }
        pause(timing.unlockDelay)
        for _ in 0 ..< timing.unlockAttempts {
            if smc.write(key, bytes: manual) {
                return true
            }
            pause(timing.retryDelay)
        }
        _ = releaseTestModeIfIdle()
        return false
    }

    private func restoreFan(_ fan: Int) -> Bool {
        guard let key = modeKey(fan), let mode = smc.read(key), let number = mode.number else { return false }
        guard FanReading.isManualMode(number) else { return true }
        if let system = mode.encoded(Mode.system), smc.write(key, bytes: system),
           smc.read(key)?.number == Mode.system
        {
            return true
        }
        guard let automatic = mode.encoded(Mode.automatic) else { return false }
        return writeConfirmed(key, bytes: automatic) { !FanReading.isManualMode($0) }
    }

    private func releaseTestModeIfIdle() -> Bool {
        guard !hasManualFans else { return true }
        guard let test = smc.read("Ftst") else { return !hasTestKey }
        hasTestKey = true
        guard test.number != 0 else { return true }
        guard let off = test.encoded(0) else { return false }
        return writeConfirmed("Ftst", bytes: off) { $0 == 0 }
    }

    /// The SMC can accept a write and keep the old value, so only the readback counts.
    private func writeConfirmed(_ key: String, bytes: [UInt8], until isDone: (Double) -> Bool) -> Bool {
        for attempt in 0 ..< timing.restoreAttempts {
            if smc.write(key, bytes: bytes), smc.read(key)?.number.map(isDone) == true {
                return true
            }
            if attempt < timing.restoreAttempts - 1 {
                pause(timing.retryDelay)
            }
        }
        return false
    }
}

/// Decides when the helper must take fans back: the app left, or went silent for too long.
public struct FanWatchdog: Sendable {
    public static let timeout = 10.0

    private var lastContact: TimeInterval
    private var clients = 0

    public init(now: TimeInterval) {
        lastContact = now
    }

    /// Counts a connection but does not restart the timer: at this point the client's signature is
    /// unchecked. Only messages, which the check lets through, prove that the app is alive.
    public mutating func clientConnected() {
        clients += 1
    }

    /// True when that was the last client, so fans must return to Auto right away.
    public mutating func clientLeft() -> Bool {
        clients = max(clients - 1, 0)
        return clients == 0
    }

    public mutating func contact(at time: TimeInterval) {
        lastContact = time
    }

    public func hasExpired(at time: TimeInterval) -> Bool {
        time - lastContact > Self.timeout
    }
}
