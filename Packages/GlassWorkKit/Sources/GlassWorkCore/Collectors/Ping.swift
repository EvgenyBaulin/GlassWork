import Foundation

public enum PingOutcome: Sendable, Equatable {
    case reply(milliseconds: Double)
    case timeout
    case unresolved
    case offline
}

public enum PingParser {
    public static func outcome(_ output: ProcessOutput) -> PingOutcome {
        if let match = output.stdout.firstMatch(of: /time=([0-9.]+) ms/), let value = Double(match.1) {
            return .reply(milliseconds: value)
        }
        let errors = output.stderr
        if errors.contains("cannot resolve") {
            return .unresolved
        }
        let offline = ["No route to host", "Network is down", "Can't assign requested address"]
        return offline.contains(where: errors.contains) ? .offline : .timeout
    }
}

public enum PingHost {
    public static let fallback = "1.1.1.1"

    /// Settings can be edited by hand, and a value like `-f` must never reach ping as an option.
    public static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else { return false }
        return host.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
        }
    }
}

public struct PingStats: Sendable, Equatable {
    public let minimum: Double
    public let average: Double
    public let maximum: Double
    /// Mean difference between neighbouring replies.
    public let jitter: Double
    /// Share of samples without a reply.
    public let loss: Double
}

/// The last 30 minutes of echoes, one per 30 seconds.
public struct PingLog: Sendable, Equatable {
    public struct Sample: Sendable, Equatable {
        public let date: Date
        public let outcome: PingOutcome

        public init(date: Date, outcome: PingOutcome) {
            self.date = date
            self.outcome = outcome
        }

        public var milliseconds: Double? {
            if case let .reply(value) = outcome {
                return value
            }
            return nil
        }
    }

    /// One echo every 30 seconds, the default.
    public static let capacity = 60
    /// Misses in a row before the host counts as down.
    public static let downAfter = 3
    /// What the log covers, however often the host is asked.
    private static let span = 1800

    public private(set) var samples: [Sample] = []
    private var limit = PingLog.capacity

    public init(samples: [Sample] = []) {
        self.samples = Array(samples.suffix(Self.capacity))
    }

    public mutating func append(_ outcome: PingOutcome, at date: Date) {
        samples.append(Sample(date: date, outcome: outcome))
        trim()
    }

    /// Keeps the same half hour when the pace changes.
    public mutating func follow(intervalSeconds: Int) {
        limit = max(Self.span / max(intervalSeconds, 1), 1)
        trim()
    }

    private mutating func trim() {
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }

    public var latest: Sample? {
        samples.last
    }

    public var replies: [Double] {
        samples.compactMap(\.milliseconds)
    }

    /// Red only when the network works and this host stays silent.
    public var isDown: Bool {
        samples.count >= Self.downAfter && samples.suffix(Self.downAfter).allSatisfy { $0.outcome == .timeout }
    }

    /// Nothing can be said about the host while the Mac itself has no network.
    public var isOffline: Bool {
        latest?.outcome == .offline || latest?.outcome == .unresolved
    }

    public var stats: PingStats? {
        let values = replies
        guard let minimum = values.min(), let maximum = values.max() else { return nil }
        let steps = zip(values, values.dropFirst()).map { abs($0 - $1) }
        return PingStats(
            minimum: minimum,
            average: values.reduce(0, +) / Double(values.count),
            maximum: maximum,
            jitter: steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count),
            loss: 1 - Double(values.count) / Double(samples.count)
        )
    }

    /// The first reply of the unbroken run that reaches the latest sample.
    public var upSince: Date? {
        samples.reversed().prefix { $0.milliseconds != nil }.last?.date
    }

    /// Replies as chart points; a missed echo leaves a gap.
    public var latency: [History<Double>.Point] {
        samples.compactMap { sample in
            sample.milliseconds.map { History<Double>.Point(date: sample.date, value: $0) }
        }
    }

    /// Loss up to each sample, for the chart's hover readout.
    public var rollingLoss: [History<Double>.Point] {
        var missed = 0.0
        return samples.enumerated().map { index, sample in
            missed += sample.milliseconds == nil ? 1 : 0
            return History<Double>.Point(date: sample.date, value: missed / Double(index + 1))
        }
    }
}

public struct PingCollector: Sendable {
    private let runner: ProcessRunning

    public init(runner: ProcessRunning) {
        self.runner = runner
    }

    /// - Parameter timeoutSeconds: How long to wait for the reply. The process gets a little longer to exit.
    public func read(host: String, timeoutSeconds: Int = 3) async -> PingOutcome {
        guard PingHost.isValid(host) else { return .unresolved }
        let arguments = Self.arguments(host: host, timeoutSeconds: timeoutSeconds)
        let limit = TimeInterval(timeoutSeconds + 2)
        guard let output = try? await runner.run("/sbin/ping", arguments: arguments, timeout: limit) else {
            return .timeout
        }
        return PingParser.outcome(output)
    }

    static func arguments(host: String, timeoutSeconds: Int) -> [String] {
        ["-n", "-c", "1", "-t", String(timeoutSeconds), "--", host]
    }
}
