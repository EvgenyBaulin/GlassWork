import Foundation
@testable import GlassWorkCore
import Testing

struct HiddenBarTests {
    private let start = Date(timeIntervalSince1970: 1000)

    private func machine(
        alwaysHidden: Bool = false,
        hover: Bool = false,
        delay: HiddenBarHoverDelay = .medium,
        seconds: Int = 10
    ) -> HiddenBarMachine {
        var settings = HidingSettings()
        settings.isEnabled = true
        settings.hasAlwaysHidden = alwaysHidden
        settings.showsOnHover = hover
        settings.hoverDelay = delay
        settings.autoHideSeconds = seconds
        var result = HiddenBarMachine()
        result.configure(settings)
        return result
    }

    @Test func turningHidingOnStartsCollapsed() {
        let machine = machine()
        #expect(machine.phase == .collapsed)
        #expect(machine.layout == HiddenBarLayout(separator: .wide, alwaysHidden: nil))
    }

    @Test func disabledHidingNeverCollapses() {
        var machine = HiddenBarMachine()
        machine.toggle(option: false, now: start)
        #expect(machine.layout == HiddenBarLayout(separator: .thin, alwaysHidden: nil))
        #expect(machine.nextDeadline == nil)
    }

    @Test func aClickRevealsThenCollapses() {
        var machine = machine()
        machine.toggle(option: false, now: start)
        #expect(machine.phase == .revealed)
        #expect(machine.layout.separator == .thin)
        machine.toggle(option: false, now: start)
        #expect(machine.phase == .collapsed)
        #expect(machine.nextDeadline == nil)
    }

    @Test func theBarCollapsesAfterTheTimeout() {
        var machine = machine(seconds: 5)
        machine.toggle(option: false, now: start)
        #expect(machine.nextDeadline == start.addingTimeInterval(5))
        machine.tick(now: start.addingTimeInterval(4), commandHeld: false, pointerInZone: false)
        #expect(machine.phase == .revealed)
        machine.tick(now: start.addingTimeInterval(5), commandHeld: false, pointerInZone: false)
        #expect(machine.phase == .collapsed)
    }

    @Test func holdingCommandPostponesTheCollapse() {
        var machine = machine(seconds: 5)
        machine.toggle(option: false, now: start)
        let due = start.addingTimeInterval(5)
        machine.tick(now: due, commandHeld: true, pointerInZone: false)
        #expect(machine.phase == .revealed)
        #expect(machine.nextDeadline == due.addingTimeInterval(5))
    }

    @Test func revealIfCollapsedNeverCloses() {
        var machine = machine()
        machine.revealIfCollapsed(now: start)
        #expect(machine.phase == .revealed)
        machine.revealIfCollapsed(now: start)
        #expect(machine.phase == .revealed)
    }

    // MARK: Always-hidden section

    @Test func alwaysHiddenLengthsFollowThePhase() {
        var machine = machine(alwaysHidden: true)
        #expect(machine.layout == HiddenBarLayout(separator: .wide, alwaysHidden: .thin))
        machine.toggle(option: false, now: start)
        #expect(machine.layout == HiddenBarLayout(separator: .thin, alwaysHidden: .wide))
        machine.toggle(option: true, now: start)
        #expect(machine.phase == .revealedAll)
        #expect(machine.layout == HiddenBarLayout(separator: .thin, alwaysHidden: .thin))
    }

    @Test func optionFromCollapsedRevealsEverything() {
        var machine = machine(alwaysHidden: true)
        machine.toggle(option: true, now: start)
        #expect(machine.phase == .revealedAll)
        machine.toggle(option: false, now: start)
        #expect(machine.phase == .collapsed)
    }

    @Test func optionDoesNothingExtraWithoutTheSection() {
        var machine = machine(alwaysHidden: false)
        machine.toggle(option: true, now: start)
        #expect(machine.phase == .revealed)
        #expect(machine.layout.alwaysHidden == nil)
    }

    @Test func turningTheSectionOffFallsBackToRevealed() {
        var machine = machine(alwaysHidden: true)
        machine.toggle(option: true, now: start)
        var settings = HidingSettings()
        settings.isEnabled = true
        machine.configure(settings)
        #expect(machine.phase == .revealed)
        #expect(machine.layout == HiddenBarLayout(separator: .thin, alwaysHidden: nil))
    }

    @Test func turningHidingOffShowsEverything() {
        var machine = machine(alwaysHidden: true)
        machine.configure(HidingSettings())
        #expect(machine.layout == HiddenBarLayout(separator: .thin, alwaysHidden: nil))
        #expect(machine.nextDeadline == nil)
    }

    // MARK: Hover

    @Test func restingAtTheSeparatorOpensAfterTheDelay() {
        var machine = machine(hover: true, delay: .medium)
        machine.pointerMoved(inZone: true, now: start)
        #expect(machine.phase == .collapsed)
        #expect(machine.nextDeadline == start.addingTimeInterval(0.6))
        machine.tick(now: start.addingTimeInterval(0.5), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .collapsed)
        machine.tick(now: start.addingTimeInterval(0.6), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .revealed)
    }

    @Test func leavingBeforeTheDelayCancelsTheOpening() {
        var machine = machine(hover: true, delay: .short)
        machine.pointerMoved(inZone: true, now: start)
        machine.pointerMoved(inZone: false, now: start.addingTimeInterval(0.1))
        #expect(machine.nextDeadline == nil)
        machine.tick(now: start.addingTimeInterval(1), commandHeld: false, pointerInZone: false)
        #expect(machine.phase == .collapsed)
    }

    @Test func aLaterMoveInTheZoneOpensWithoutATick() {
        var machine = machine(hover: true, delay: .short)
        machine.pointerMoved(inZone: true, now: start)
        machine.pointerMoved(inZone: true, now: start.addingTimeInterval(0.4))
        #expect(machine.phase == .revealed)
    }

    @Test func hoverIsIgnoredWhenOff() {
        var machine = machine(hover: false)
        machine.pointerMoved(inZone: true, now: start)
        machine.tick(now: start.addingTimeInterval(5), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .collapsed)
    }

    @Test func aHoverOpeningStaysWhileThePointerStaysAndCollapsesAfterLeaving() {
        var machine = machine(hover: true, delay: .short, seconds: 5)
        machine.pointerMoved(inZone: true, now: start)
        machine.tick(now: start.addingTimeInterval(0.3), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .revealed)
        // Still at the separator when the timeout comes: it waits.
        machine.tick(now: start.addingTimeInterval(5.3), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .revealed)
        machine.pointerMoved(inZone: true, now: start.addingTimeInterval(8))
        #expect(machine.nextDeadline == start.addingTimeInterval(13))
        // Left: the timeout from the last move runs out.
        machine.tick(now: start.addingTimeInterval(13), commandHeld: false, pointerInZone: false)
        #expect(machine.phase == .collapsed)
    }

    @Test func aClickOpeningCollapsesEvenWithThePointerAtTheSeparator() {
        var machine = machine(hover: true, seconds: 5)
        machine.toggle(option: false, now: start)
        machine.tick(now: start.addingTimeInterval(5), commandHeld: false, pointerInZone: true)
        #expect(machine.phase == .collapsed)
    }

    @Test func theZoneChecksHeightFirst() {
        let inBar = CGPoint(x: 995, y: 995)
        #expect(HiddenBarZone.contains(inBar, separatorMaxX: 1000, screenMaxY: 1000, barHeight: 24))
        #expect(!HiddenBarZone.contains(CGPoint(x: 995, y: 900), separatorMaxX: 1000, screenMaxY: 1000, barHeight: 24))
        #expect(!HiddenBarZone.contains(CGPoint(x: 900, y: 995), separatorMaxX: 1000, screenMaxY: 1000, barHeight: 24))
        #expect(!HiddenBarZone.contains(CGPoint(x: 1010, y: 995), separatorMaxX: 1000, screenMaxY: 1000, barHeight: 24))
    }
}

struct HidingSettingsDecodingTests {
    @Test func anOldFileKeepsItsValuesAndGetsDefaults() throws {
        let json = #"{"isEnabled": true, "autoHideSeconds": 20}"#
        let settings = try JSONDecoder().decode(HidingSettings.self, from: Data(json.utf8))
        #expect(settings.isEnabled)
        #expect(settings.autoHideSeconds == 20)
        #expect(!settings.hasAlwaysHidden)
        #expect(!settings.showsOnHover)
        #expect(settings.hoverDelay == .medium)
    }

    @Test func newKeysRoundTrip() throws {
        var settings = HidingSettings()
        settings.hasAlwaysHidden = true
        settings.showsOnHover = true
        settings.hoverDelay = .long
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(HidingSettings.self, from: data) == settings)
    }

    @Test func aBrokenDelayFallsBackWithoutLosingTheRest() throws {
        let json = #"{"isEnabled": true, "hoverDelay": 7, "showsOnHover": true}"#
        let settings = try JSONDecoder().decode(HidingSettings.self, from: Data(json.utf8))
        #expect(settings.isEnabled)
        #expect(settings.showsOnHover)
        #expect(settings.hoverDelay == .medium)
    }

    @Test func theShortcutHasStableIdAndNoDefaultKeys() {
        #expect(ShortcutAction.hiddenBar.id == "hiddenBar")
        #expect(ShortcutAction.hiddenBar.defaultShortcut == nil)
        #expect(ShortcutAction.all.contains(.hiddenBar))
    }
}
