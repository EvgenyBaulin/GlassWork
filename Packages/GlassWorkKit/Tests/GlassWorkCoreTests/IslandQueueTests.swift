import Foundation
@testable import GlassWorkCore
import Testing

struct IslandQueueTests {
    private let now = Date(timeIntervalSince1970: 1000)

    @Test func importanceMatchesDeclaredOrder() {
        #expect(IslandEventKind.allCases.map(\.rawValue) == [
            "meeting", "inProgress", "timers", "systemAlert", "network", "build", "devServers", "charging",
            "keepAwake", "focus", "nowPlaying", "weather", "copied", "downloads", "airPods", "volume", "agents",
        ])
        #expect(IslandEventKind.allCases.map(\.importance) == Array(0 ..< 17))
    }

    @Test func ordersImportanceThenNewestAndAssignsWings() {
        let old = event("old", kind: .timers)
        var new = event("new", kind: .timers)
        new.since = now.addingTimeInterval(1)
        let meeting = event("meeting", kind: .meeting)
        let queue = IslandQueue(events: [old, new, meeting])
        #expect(queue.ordered.map(\.id) == ["meeting", "new", "old"])
        #expect(queue.pages == queue.ordered)
        #expect(queue.wings.left == meeting)
        #expect(queue.wings.right == new)
        #expect(queue.wings.hasMore)
    }

    @Test func emptyAndSingleWings() {
        var queue = IslandQueue()
        #expect(queue.wings.left == nil)
        #expect(queue.wings.right == nil)
        #expect(!queue.wings.hasMore)
        queue.events = [event("one", kind: .timers)]
        #expect(queue.wings.left?.id == "one")
        #expect(queue.wings.right == nil)
        #expect(!queue.wings.hasMore)
        queue.events.append(event("two", kind: .timers))
        #expect(!queue.wings.hasMore)
    }

    @Test func expiresAtExactDeadlineAndDismissesStableID() {
        var transient = event("temporary", kind: .timers)
        transient.expires = now.addingTimeInterval(4)
        var queue = IslandQueue(events: [event("ongoing", kind: .timers), transient])
        queue.removeExpired(at: now.addingTimeInterval(3.999))
        #expect(queue.events.count == 2)
        queue.removeExpired(at: now.addingTimeInterval(4))
        #expect(queue.events.map(\.id) == ["ongoing"])
        queue.dismiss(id: "absent")
        #expect(queue.events.count == 1)
        queue.dismiss(id: "ongoing")
        #expect(queue.events.isEmpty)
    }

    private func event(_ id: String, kind: IslandEventKind) -> IslandEvent {
        IslandEvent(id: id, kind: kind, since: now, detail: .timers([]))
    }
}
