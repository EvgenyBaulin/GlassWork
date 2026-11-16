import Foundation

public struct IslandQueue: Sendable, Equatable {
    public var events: [IslandEvent]

    public init(events: [IslandEvent] = []) {
        self.events = events
    }

    public var ordered: [IslandEvent] {
        events.sorted {
            if $0.kind.importance != $1.kind.importance {
                return $0.kind.importance < $1.kind.importance
            }
            if $0.since != $1.since {
                return $0.since > $1.since
            }
            return $0.id < $1.id
        }
    }

    // The two occupants and overflow flag describe one queue projection.
    // swiftlint:disable:next large_tuple
    public var wings: (left: IslandEvent?, right: IslandEvent?, hasMore: Bool) {
        let sorted = ordered
        return (sorted.first, sorted.dropFirst().first, sorted.count > 2)
    }

    public var pages: [IslandEvent] {
        ordered
    }

    public mutating func removeExpired(at date: Date) {
        events.removeAll { $0.expires.map { $0 <= date } ?? false }
    }

    public mutating func dismiss(id: String) {
        events.removeAll { $0.id == id }
    }
}
