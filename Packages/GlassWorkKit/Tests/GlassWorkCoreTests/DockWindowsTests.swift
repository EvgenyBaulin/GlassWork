import CoreGraphics
import Foundation
@testable import GlassWorkCore
import Testing

struct DockWindowsTests {
    private func raw(
        _ id: Int,
        pid: Int32 = 7,
        layer: Int = 0,
        title: String? = nil,
        x: CGFloat = 0,
        size: CGSize = CGSize(width: 800, height: 600),
        alpha: Double = 1
    ) -> DockWindows.Raw {
        DockWindows.Raw(
            id: id,
            pid: pid,
            layer: layer,
            bounds: CGRect(origin: CGPoint(x: x, y: 40), size: size),
            title: title,
            alpha: alpha
        )
    }

    @Test func onlyTheAppsOrdinaryWindowsAreListedInOrder() {
        let windows = [
            raw(1, title: "Inbox"),
            raw(2, pid: 9, title: "Other app"),
            raw(3, layer: 25, title: "Menu bar item"),
            raw(4, size: CGSize(width: 20, height: 20)),
            raw(5, alpha: 0),
            raw(6, title: "Drafts"),
        ]
        let items = DockWindows.items(from: windows, pid: 7)
        #expect(items.map(\.id) == [1, 6])
        #expect(items.map(\.title) == ["Inbox", "Drafts"])
    }

    /// Without Screen Recording the window server leaves titles out, and the menu says "Window 1", "Window 2".
    @Test func windowsWithoutTitlesAreNumberedByPlace() {
        let items = DockWindows.items(from: [raw(1), raw(2, title: ""), raw(3, title: "  ")], pid: 7)
        #expect(items.map(\.title) == [nil, nil, nil])
        #expect(items.map(\.number) == [1, 2, 3])
    }

    @Test func aMixOfTitledAndUntitledNumbersEveryLineByItsPlace() {
        let items = DockWindows.items(from: [raw(1, title: "Inbox"), raw(2), raw(3, title: "Drafts"), raw(4)], pid: 7)
        #expect(items.map(\.title) == ["Inbox", nil, "Drafts", nil])
        #expect(items.map(\.number) == [1, 2, 3, 4])
    }

    @Test func noWindowsGiveAnEmptyList() {
        #expect(DockWindows.items(from: [], pid: 7).isEmpty)
        #expect(DockWindows.items(from: [raw(1, pid: 9)], pid: 7).isEmpty)
    }

    @Test func aWindowIsMatchedByItsPlaceAndSize() {
        let item = DockWindows.items(from: [raw(1, x: 100)], pid: 7)[0]
        let elements = [
            DockWindows.Element(title: "A", frame: CGRect(x: 0, y: 40, width: 800, height: 600)),
            DockWindows.Element(title: "B", frame: CGRect(x: 101, y: 41, width: 800, height: 600)),
        ]
        #expect(DockWindows.match(item, in: elements) == 1)
    }

    @Test func twoWindowsInTheSamePlaceAreToldApartByTitle() {
        let item = DockWindows.items(from: [raw(1, title: "Second")], pid: 7)[0]
        let frame = CGRect(x: 0, y: 40, width: 800, height: 600)
        let elements = [
            DockWindows.Element(title: "First", frame: frame),
            DockWindows.Element(title: "Second", frame: frame),
        ]
        #expect(DockWindows.match(item, in: elements) == 1)
    }

    @Test func aWindowThatIsNowhereIsNotMatched() {
        let item = DockWindows.items(from: [raw(1, x: 500)], pid: 7)[0]
        let elements = [DockWindows.Element(title: "A", frame: CGRect(x: 0, y: 40, width: 800, height: 600))]
        #expect(DockWindows.match(item, in: elements) == nil)
    }

    @Test func newWindowIsTheItemOnCommandNAlone() {
        #expect(DockWindows.isCommandN(character: "n", modifiers: 0))
        #expect(DockWindows.isCommandN(character: "N", modifiers: 0))
        // ⇧⌘N is 1, ⌥⌘N is 2, and a bare N has the Command bit (8) off.
        #expect(!DockWindows.isCommandN(character: "N", modifiers: 1))
        #expect(!DockWindows.isCommandN(character: "N", modifiers: 2))
        #expect(!DockWindows.isCommandN(character: "N", modifiers: 8))
        #expect(!DockWindows.isCommandN(character: "T", modifiers: 0))
        #expect(!DockWindows.isCommandN(character: nil, modifiers: nil))
    }
}

struct DockWindowMatchingTests {
    private let frame = CGRect(x: 0, y: 40, width: 800, height: 600)

    private func item(_ id: Int, number: Int, title: String? = nil) -> DockWindowItem {
        DockWindowItem(id: id, title: title, number: number, bounds: frame)
    }

    @Test func untitledWindowsWithTheSameBoundsAreMatchedByOrder() {
        let items = [item(1, number: 1), item(2, number: 2), item(3, number: 3)]
        let elements = [DockWindows.Element(title: nil, frame: frame), DockWindows.Element(title: nil, frame: frame)]
        #expect(DockWindows.match(items[0], among: items, in: elements) == 0)
        #expect(DockWindows.match(items[1], among: items, in: elements) == 1)
        // More windows than elements: the last element is the closest answer.
        #expect(DockWindows.match(items[2], among: items, in: elements) == 1)
    }

    @Test func orderCountsOnlyWindowsInTheSamePlace() {
        let other = DockWindowItem(id: 9, title: nil, number: 1, bounds: CGRect(x: 300, y: 40, width: 800, height: 600))
        let items = [other, item(1, number: 2), item(2, number: 3)]
        let elements = [DockWindows.Element(title: nil, frame: frame), DockWindows.Element(title: nil, frame: frame)]
        #expect(DockWindows.match(items[2], among: items, in: elements) == 1)
    }

    @Test func titledDuplicatesAreMatchedByOrderWithinTheTitle() {
        let items = [item(1, number: 1, title: "A"), item(2, number: 2, title: "B"), item(3, number: 3, title: "B")]
        let elements = [
            DockWindows.Element(title: "B", frame: frame),
            DockWindows.Element(title: "A", frame: frame),
            DockWindows.Element(title: "B", frame: frame),
        ]
        #expect(DockWindows.match(items[0], among: items, in: elements) == 1)
        #expect(DockWindows.match(items[1], among: items, in: elements) == 0)
        #expect(DockWindows.match(items[2], among: items, in: elements) == 2)
    }

    @Test func aMinimizedWindowIsRestoredBeforeRaising() {
        #expect(DockWindows.needsRestore(DockWindows.Element(title: nil, frame: frame, minimized: true)))
        #expect(!DockWindows.needsRestore(DockWindows.Element(title: nil, frame: frame)))
    }
}

struct DockAnswerCacheTests {
    @Test func anAnswerHoldsUntilItsLifetimeEnds() {
        var cache = DockAnswerCache<Int32>(lifetime: 30)
        let start = Date(timeIntervalSince1970: 1000)
        #expect(cache.value(for: 5, now: start) == nil)
        cache.store(true, for: 5, now: start)
        #expect(cache.value(for: 5, now: start.addingTimeInterval(29)) == true)
        #expect(cache.value(for: 5, now: start.addingTimeInterval(30)) == nil)
        #expect(cache.value(for: 6, now: start) == nil)
    }

    @Test func aNewAnswerReplacesTheOldOne() {
        var cache = DockAnswerCache<Int32>()
        let start = Date(timeIntervalSince1970: 1000)
        cache.store(true, for: 5, now: start)
        cache.store(false, for: 5, now: start.addingTimeInterval(40))
        #expect(cache.value(for: 5, now: start.addingTimeInterval(41)) == false)
    }
}
