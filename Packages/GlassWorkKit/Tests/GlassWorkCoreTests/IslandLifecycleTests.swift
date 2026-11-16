import Foundation
@testable import GlassWorkCore
import Testing

struct IslandLifecycleTests {
    private let now = Date(timeIntervalSince1970: 1000)

    @Test func peekDeadlineAndExit() {
        var state = IslandLifecycle()
        #expect(state.nextDeadline == nil)
        state.pointerEntered(at: now)
        #expect(state.nextDeadline == now.addingTimeInterval(0.15))
        state.tick(at: now.addingTimeInterval(0.149))
        #expect(state.phase == .idle)
        state.tick(at: now.addingTimeInterval(0.15))
        #expect(state.phase == .peek)
        #expect(state.nextDeadline == nil)
        state.pointerExited(at: now.addingTimeInterval(0.2))
        #expect(state.phase == .idle)
    }

    @Test func leavingCancelsPeekAndReentryRestartsDelay() {
        var state = IslandLifecycle()
        state.pointerEntered(at: now)
        state.pointerExited(at: now.addingTimeInterval(0.1))
        state.tick(at: now.addingTimeInterval(1))
        #expect(state.phase == .idle)
        #expect(state.nextDeadline == nil)
        state.pointerEntered(at: now.addingTimeInterval(1))
        state.pointerEntered(at: now.addingTimeInterval(1.1))
        state.tick(at: now.addingTimeInterval(1.151))
        #expect(state.phase == .peek)
    }

    @Test func eventsDriveCompactWithoutAffectingExpanded() {
        var state = IslandLifecycle()
        state.eventsChanged(hasEvents: true)
        #expect(state.phase == .compact)
        state.clicked()
        #expect(state.phase == .expanded)
        state.eventsChanged(hasEvents: false)
        #expect(state.phase == .expanded)
        state.escape()
        #expect(state.phase == .idle)
        state.eventsChanged(hasEvents: true)
        state.eventsChanged(hasEvents: false)
        #expect(state.phase == .idle)
    }

    @Test func clicksWithoutEventsStayPeek() {
        var state = IslandLifecycle()
        state.clicked()
        #expect(state.phase == .peek)
        state.clicked()
        #expect(state.phase == .peek)
        state.pointerEntered(at: now)
        state.tick(at: now.addingTimeInterval(1))
        #expect(state.phase == .peek)
        #expect(state.nextDeadline == nil)
    }

    @Test func enabledHoverOnlyPeeksWithoutEvents() {
        var state = IslandLifecycle(hoverToExpand: true)
        state.pointerEntered(at: now)
        state.tick(at: now.addingTimeInterval(0.149))
        #expect(state.phase == .idle)
        state.tick(at: now.addingTimeInterval(0.15))
        #expect(state.phase == .peek)
        #expect(state.nextDeadline == nil)
        state.tick(at: now.addingTimeInterval(1))
        #expect(state.phase == .peek)
    }

    @Test func enabledHoverExpandsAnEvent() {
        var state = IslandLifecycle(hoverToExpand: true)
        state.eventsChanged(hasEvents: true)
        state.pointerEntered(at: now)
        #expect(state.nextDeadline == now.addingTimeInterval(0.3))
        state.tick(at: now.addingTimeInterval(0.299))
        #expect(state.phase == .compact)
        state.tick(at: now.addingTimeInterval(0.301))
        #expect(state.phase == .expanded)
        state.clickedOutside()
        #expect(state.phase == .compact)
    }

    @Test func hoverExpansionUsesOriginalEntryTime() {
        var state = IslandLifecycle(hoverToExpand: true)
        state.pointerEntered(at: now)
        state.tick(at: now.addingTimeInterval(0.151))
        #expect(state.phase == .peek)
        state.eventsChanged(hasEvents: true)
        #expect(state.nextDeadline == now.addingTimeInterval(0.3))
        state.tick(at: now.addingTimeInterval(0.299))
        #expect(state.phase == .compact)
        state.tick(at: now.addingTimeInterval(0.3))
        #expect(state.phase == .expanded)
        #expect(state.nextDeadline == nil)
    }

    @Test func hoverExpansionCanBeDisabled() {
        var state = IslandLifecycle()
        state.eventsChanged(hasEvents: true)
        state.pointerEntered(at: now)
        state.tick(at: now.addingTimeInterval(10))
        #expect(state.phase == .compact)
        #expect(state.nextDeadline == nil)
        state.hoverToExpand = true
        #expect(state.nextDeadline == now.addingTimeInterval(0.3))
        state.tick(at: now.addingTimeInterval(10))
        #expect(state.phase == .expanded)
    }

    @Test func exitCollapseDeadlineAndReentryCancellation() {
        var state = IslandLifecycle()
        state.eventsChanged(hasEvents: true)
        state.clicked()
        state.pointerExited(at: now)
        state.pointerExited(at: now.addingTimeInterval(0.5))
        #expect(state.nextDeadline == now.addingTimeInterval(1))
        state.tick(at: now.addingTimeInterval(0.999))
        #expect(state.phase == .expanded)
        state.pointerEntered(at: now.addingTimeInterval(0.999))
        state.tick(at: now.addingTimeInterval(2))
        #expect(state.phase == .expanded)
        state.pointerExited(at: now.addingTimeInterval(2))
        state.tick(at: now.addingTimeInterval(3))
        #expect(state.phase == .compact)
        #expect(state.nextDeadline == nil)
    }

    @Test(arguments: ["click", "outside", "escape", "exit"])
    func collapseActions(action: String) {
        var state = IslandLifecycle()
        state.eventsChanged(hasEvents: true)
        state.clicked()
        switch action {
        case "click": state.clicked()
        case "outside": state.clickedOutside()
        case "escape": state.escape()
        default:
            state.pointerExited(at: now)
            state.tick(at: now.addingTimeInterval(1.001))
        }
        #expect(state.phase == .compact)
        state.tick(at: now.addingTimeInterval(10))
        #expect(state.phase == .compact)
    }

    @Test func escapeAndOutsideDoNotChangeCollapsedPhases() {
        var state = IslandLifecycle()
        state.escape()
        state.clickedOutside()
        #expect(state.phase == .idle)
        state.clicked()
        state.escape()
        state.clickedOutside()
        #expect(state.phase == .peek)
    }
}
