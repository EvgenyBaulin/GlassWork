import Foundation

/// Answers that are slow to find and stay true for a while, kept per key. The clock is passed in, so expiry is
/// testable.
public struct DockAnswerCache<Key: Hashable & Sendable>: Sendable {
    public let lifetime: TimeInterval
    private var entries: [Key: (value: Bool, stored: Date)] = [:]

    public init(lifetime: TimeInterval = 30) {
        self.lifetime = lifetime
    }

    /// The answer for the key, or nil when there is none or it is older than the lifetime.
    public func value(for key: Key, now: Date) -> Bool? {
        guard let entry = entries[key], now.timeIntervalSince(entry.stored) < lifetime else { return nil }
        return entry.value
    }

    public mutating func store(_ value: Bool, for key: Key, now: Date) {
        entries[key] = (value, now)
    }
}
