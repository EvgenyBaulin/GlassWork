import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct IslandShelfDropTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theDropEventExpiresAfterAFewSeconds() {
        let event = IslandEventBuilder.shelfDrop(count: 2, now: now)

        #expect(event.kind == .shelfDrop)
        #expect(event.detail == .shelfDrop(count: 2))
        #expect(event.expires == now.addingTimeInterval(IslandEventBuilder.transientDuration))
        #expect(event.isTransition)
    }

    @Test func aDropShowsCompactAndGoesAway() {
        let store = IslandStore()
        store.update(input: IslandInput(), now: now)

        store.showShelfDrop(count: 2, now: now)

        #expect(store.lifecycle.phase == .compact)
        #expect(store.queue.events.map(\.detail) == [.shelfDrop(count: 2)])

        store.tick(now: now.addingTimeInterval(IslandEventBuilder.transientDuration + 1))

        #expect(store.queue.events.isEmpty)
        #expect(store.lifecycle.phase == .idle)
    }

    @Test func theDropOutlivesTheNextSnapshot() {
        let store = IslandStore()
        store.update(input: IslandInput(), now: now)
        store.showShelfDrop(count: 3, now: now)

        store.update(input: IslandInput(), now: now.addingTimeInterval(1))

        #expect(store.queue.events.map(\.detail) == [.shelfDrop(count: 3)])
    }

    @Test func dropsCloseTogetherAddUp() {
        let store = IslandStore()
        store.showShelfDrop(count: 2, now: now)
        store.showShelfDrop(count: 1, now: now.addingTimeInterval(2))

        #expect(store.queue.events.map(\.detail) == [.shelfDrop(count: 3)])

        store.showShelfDrop(count: 4, now: now.addingTimeInterval(30))

        #expect(store.queue.events.map(\.detail) == [.shelfDrop(count: 4)])
    }

    @Test func nothingDroppedShowsNothing() {
        let store = IslandStore()
        store.showShelfDrop(count: 0, now: now)

        #expect(store.queue.events.isEmpty)
    }

    @Test func thePreviewFollowsTheDragAndResets() {
        let store = IslandStore()
        let preview = IslandDropPreview(names: ["a.pdf", "b.md"], onShelf: 3)

        store.beginDrop(preview)
        #expect(store.dropPreview == preview)

        store.endDrop()
        #expect(store.dropPreview == nil)

        store.beginDrop(preview)
        store.reset()
        #expect(store.dropPreview == nil)
    }

    @Test func thePreviewListsTwoNamesAndCountsTheRest() {
        #expect(IslandDropPreview(names: ["a.pdf"], onShelf: 0).listedNames == "a.pdf")
        #expect(IslandDropPreview(names: ["a.pdf", "b.md"], onShelf: 0).listedNames == "a.pdf, b.md")

        let many = IslandDropPreview(
            urls: ["a", "b", "c", "d"].map { URL(filePath: "/tmp/\($0).txt") }, onShelf: 1
        )
        #expect(many.count == 4)
        #expect(many.listedNames == "a.txt, b.txt +2")
    }

    @Test func theDropTriggerIsTheNotchWithASmallMargin() {
        let geometry = IslandGeometry(screen: IslandScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32,
            auxiliaryLeftWidth: 628, auxiliaryRightWidth: 628, menuBarHeight: 32
        ))
        let trigger = geometry.dropTriggerFrame

        #expect(trigger.contains(CGPoint(x: 720, y: 890)))
        #expect(trigger.contains(CGPoint(x: geometry.notch.minX - 30, y: 880)))
        #expect(!trigger.contains(CGPoint(x: geometry.notch.minX - 60, y: 890)))
        #expect(!trigger.contains(CGPoint(x: 720, y: 800)))
        #expect(trigger.maxY == geometry.notch.maxY)
    }
}
