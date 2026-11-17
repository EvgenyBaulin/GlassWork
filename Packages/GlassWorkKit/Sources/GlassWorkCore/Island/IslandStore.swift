import Foundation
import Observation

@MainActor
@Observable
public final class IslandStore {
    public private(set) var queue = IslandQueue()
    public var lifecycle: IslandLifecycle
    public private(set) var page = 0
    /// Files being dragged over the notch; the island shows the drop zone while this is set.
    public private(set) var dropPreview: IslandDropPreview?

    /// The chosen mini widgets and what each says, for the card opened with no event on screen.
    public var miniWidgets = IslandMiniSet()
    public private(set) var miniReadings: [IslandMiniWidget: IslandMiniReading] = [:]
    /// Whether the opened card lists the widgets to choose from instead of showing them.
    public var isEditingWidgets = false

    @ObservationIgnored private var previous: IslandInput?
    @ObservationIgnored private var dismissedOngoing: Set<String> = []

    @ObservationIgnored private var snoozedUntil: [String: Date] = [:]

    public init(hoverToExpand: Bool = false) {
        lifecycle = IslandLifecycle(hoverToExpand: hoverToExpand)
    }

    public func update(input: IslandInput, now: Date) {
        snoozedUntil = snoozedUntil.filter { $0.value > now }
        let built = IslandEventBuilder.events(current: input, previous: previous, now: now)
        let active = Set(built.filter { !$0.isTransition }.map(\.id))
        dismissedOngoing.formIntersection(active)
        var merged = queue.events.filter { $0.isTransition && survives($0, input: input) }
        for var event in built where !dismissedOngoing.contains(event.id) && snoozedUntil[event.id] == nil {
            // Refresh payloads without changing how long a continuous event has been present.
            if !event.isTransition, let old = queue.events.first(where: { $0.id == event.id }) {
                event.since = old.since
            }
            merged.removeAll { $0.id == event.id }
            merged.append(event)
        }
        let context = IslandContext(input: input, now: now)
        merged = merged.map { event in
            var event = event
            var refreshed = context
            if case let .copied(entry) = event.detail, let current = input.clipboardEntry, current.id == entry.id {
                event.detail = .copied(current)
            }
            if case let .copied(entry) = event.detail, input.clipboardEntry?.id != entry.id {
                refreshed.clipboardPreview = event.context.clipboardPreview
                refreshed.clipboardImageURL = event.context.clipboardImageURL
            }
            event.context = refreshed
            return event
        }
        previous = input
        let readings = IslandMiniReading.readings(from: input, now: now)
        if readings != miniReadings {
            miniReadings = readings
        }
        // Observers redraw on every assignment, so an unchanged queue is not assigned: the surface stays
        // still while nothing happens.
        if merged != queue.events {
            queue.events = merged
        }
        tick(now: now)
    }

    public func tick(now: Date) {
        var next = queue
        next.removeExpired(at: now)
        if next != queue {
            queue = next
        }
        synchronize()
        var state = lifecycle
        state.tick(at: now)
        if state != lifecycle {
            lifecycle = state
        }
        if isEditingWidgets, lifecycle.phase != .expanded {
            isEditingWidgets = false
        }
    }

    public func dismiss(id: String) {
        if let event = queue.events.first(where: { $0.id == id }), !event.isTransition {
            dismissedOngoing.insert(id)
        }
        queue.dismiss(id: id)
        synchronize()
    }

    /// Suppresses this meeting, including its in-progress card, for five minutes.
    public func snoozeMeeting(id: String, now: Date) {
        guard let event = queue.events.first(where: { $0.id == id }),
              case let .meeting(meeting) = event.detail else { return }
        let until = now.addingTimeInterval(300)
        snoozedUntil["meeting:\(meeting.id)"] = until
        snoozedUntil["inProgress:\(meeting.id)"] = until
        queue.dismiss(id: id)
        synchronize()
    }

    public func beginDrop(_ preview: IslandDropPreview) {
        if preview != dropPreview {
            dropPreview = preview
        }
    }

    public func endDrop() {
        if dropPreview != nil {
            dropPreview = nil
        }
    }

    /// Shows how many files just went onto the shelf. Drops within a few seconds add up.
    public func showShelfDrop(count: Int, now: Date) {
        guard count > 0 else { return }
        var total = count
        if let old = queue.events.first(where: { $0.id == "shelfDrop" }),
           case let .shelfDrop(earlier) = old.detail, old.expires.map({ $0 > now }) ?? false
        {
            total += earlier
        }
        queue.events.removeAll { $0.id == "shelfDrop" }
        queue.events.append(IslandEventBuilder.shelfDrop(count: total, now: now))
        synchronize()
    }

    /// Starts fresh after disabling the surface; old transitions must not replay on re-enable.
    public func reset() {
        previous = nil
        queue = IslandQueue()
        var fresh = IslandLifecycle(hoverToExpand: lifecycle.hoverToExpand)
        fresh.opensWidgets = lifecycle.opensWidgets
        lifecycle = fresh
        isEditingWidgets = false
        miniReadings = [:]
        page = 0
        dropPreview = nil
        dismissedOngoing = []
        snoozedUntil = [:]
    }

    public func showPage(_ index: Int) {
        let clamped = min(max(index, 0), max(queue.events.count - 1, 0))
        if clamped != page {
            page = clamped
        }
    }

    private func synchronize() {
        var state = lifecycle
        state.eventsChanged(hasEvents: !queue.events.isEmpty)
        if state != lifecycle {
            lifecycle = state
        }
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
