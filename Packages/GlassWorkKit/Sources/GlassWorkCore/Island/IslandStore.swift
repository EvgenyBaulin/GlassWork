import Foundation
import Observation

@MainActor
@Observable
public final class IslandStore {
    public private(set) var queue = IslandQueue()
    public var lifecycle: IslandLifecycle
    public private(set) var page = 0

    @ObservationIgnored private var previous: IslandInput?
    @ObservationIgnored private var dismissedOngoing: Set<String> = []

    public init(hoverToExpand: Bool = false) {
        lifecycle = IslandLifecycle(hoverToExpand: hoverToExpand)
    }

    public func update(input: IslandInput, now: Date) {
        let built = IslandEventBuilder.events(current: input, previous: previous, now: now)
        let active = Set(built.filter { !$0.isTransition }.map(\.id))
        dismissedOngoing.formIntersection(active)
        var merged = queue.events.filter { $0.isTransition && survives($0, input: input) }
        for var event in built where !dismissedOngoing.contains(event.id) {
            // Refresh payloads without changing how long a continuous event has been present.
            if !event.isTransition, let old = queue.events.first(where: { $0.id == event.id }) {
                event.since = old.since
            }
            merged.removeAll { $0.id == event.id }
            merged.append(event)
        }
        previous = input
        queue.events = merged
        tick(now: now)
    }

    public func tick(now: Date) {
        queue.removeExpired(at: now)
        synchronize()
        lifecycle.tick(at: now)
    }

    public func dismiss(id: String) {
        if let event = queue.events.first(where: { $0.id == id }), !event.isTransition {
            dismissedOngoing.insert(id)
        }
        queue.dismiss(id: id)
        synchronize()
    }

    public func showPage(_ index: Int) {
        page = min(max(index, 0), max(queue.events.count - 1, 0))
    }

    private func synchronize() {
        lifecycle.eventsChanged(hasEvents: !queue.events.isEmpty)
        showPage(page)
    }

    private func survives(_ event: IslandEvent, input: IslandInput) -> Bool {
        switch event.detail {
        case .network(.wifiLost): input.wifi?.link == nil
        case .network(.vpnOff): input.vpn?.isConnected != true
        default: true
        }
    }
}
