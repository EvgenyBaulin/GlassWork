import Foundation
import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct IslandLayoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let geometry = IslandGeometry(screen: IslandScreen(
        frame: CGRect(x: -1440, y: 200, width: 1440, height: 900), safeAreaTop: 32,
        auxiliaryLeftWidth: 628, auxiliaryRightWidth: 628, menuBarHeight: 32
    ))

    @Test func compactCollisionBoundsMatchTheHitSurface() {
        let store = IslandStore()
        var input = IslandInput()
        input.timers = [CountdownTimer(title: "Tea", duration: 600, start: now)]
        store.update(input: input, now: now)
        let view = IslandView(
            store: store, geometry: geometry,
            appMenuMaxX: geometry.notch.minX - 10, statusItemsMinX: geometry.notch.maxX + 40
        )
        let frame = view.surfaceFrame(now: now)
        #expect(frame.minX == geometry.notch.minX)
        #expect(frame.maxX == geometry.notch.maxX + 40)
        #expect(frame.maxY == geometry.notch.maxY)
        #expect(view.contains(CGPoint(x: frame.midX, y: frame.midY), in: frame))
        #expect(!view.contains(CGPoint(x: frame.minX + 1, y: frame.minY + 1), in: frame))
        #expect(!view.contains(CGPoint(x: frame.maxX + 2, y: frame.midY), in: frame))
    }

    @Test func expandedLongListIsCappedAndEmptyExpandedReturnsToNotchBounds() {
        let store = IslandStore()
        var input = IslandInput()
        input.timers = (0 ..< 20).map { CountdownTimer(title: "Timer \($0)", duration: 600, start: now) }
        store.update(input: input, now: now)
        store.lifecycle.clicked()
        let view = IslandView(store: store, geometry: geometry)
        let frame = view.surfaceFrame(now: now)
        #expect(frame.width <= 480)
        #expect(frame.height == 420)
        #expect(frame.midX == geometry.notch.midX)
        #expect(frame.maxY == geometry.notch.maxY)
        store.dismiss(id: "timers")
        #expect(store.lifecycle.phase == .expanded)
        #expect(view.surfaceFrame(now: now) == geometry.notch)
    }

    @Test func virtualNotchHasNoIdleWidthAndEventsAttachToTheTopEdge() {
        let virtual = IslandGeometry(screen: IslandScreen(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0, menuBarHeight: 24
        ))
        let store = IslandStore()
        let view = IslandView(store: store, geometry: virtual)
        #expect(view.surfaceFrame(now: now).width == 0)
        var input = IslandInput()
        input.timers = [CountdownTimer(title: "Tea", duration: 600, start: now)]
        store.update(input: input, now: now)
        #expect(view.surfaceFrame(now: now).width > 0)
        #expect(view.surfaceFrame(now: now).maxY == 1080)
    }
}
