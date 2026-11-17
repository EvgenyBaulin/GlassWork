import Foundation

/// What the ping notifications announce.
public enum PingEvent: Sendable, Equatable {
    case down(host: String)
    case recovered(host: String, downFor: TimeInterval)
}

/// One pair of events per outage: "down" after 30 seconds of misses, "back" at the first reply.
public struct PingOutageTracker: Sendable {
    /// How long the host must stay silent before it counts as down.
    public static let downAfter: TimeInterval = 30

    private var host: String?
    private var lastDate: Date?
    private var firstMiss: Date?
    private var isAnnounced = false

    public init() {}

    /// Feeds one echo. Time comes in as an argument, so the same echo fed twice counts once.
    public mutating func update(host: String, outcome: PingOutcome, at date: Date) -> PingEvent? {
        if self.host != host {
            self = PingOutageTracker()
            self.host = host
        }
        if let lastDate, date <= lastDate {
            return nil
        }
        lastDate = date
        switch outcome {
        case .reply:
            defer {
                firstMiss = nil
                isAnnounced = false
            }
            guard isAnnounced, let firstMiss else { return nil }
            return .recovered(host: host, downFor: date.timeIntervalSince(firstMiss))
        case .timeout:
            let start = firstMiss ?? date
            firstMiss = start
            guard !isAnnounced, date.timeIntervalSince(start) >= Self.downAfter else { return nil }
            isAnnounced = true
            return .down(host: host)
        case .unresolved, .offline:
            // The Mac has no network: nothing can be said about the host, and a running outage carries on.
            if !isAnnounced {
                firstMiss = nil
            }
            return nil
        }
    }
}
