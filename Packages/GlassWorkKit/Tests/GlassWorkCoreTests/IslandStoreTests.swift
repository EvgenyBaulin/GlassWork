import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct IslandStoreTests {
    private let now = IslandFixtures.now

    @Test func ongoingPayloadIsReplacedWithoutChangingSince() {
        let store = IslandStore()
        var input = IslandInput()
        input.timers = [CountdownTimer(title: "Tea", duration: 60, start: now)]
        store.update(input: input, now: now)
        #expect(store.lifecycle.phase == .compact)
        input.timers[0].title = "Coffee"
        store.update(input: input, now: now.addingTimeInterval(2))
        #expect(store.queue.events.count == 1)
        #expect(store.queue.events.first?.since == now)
        #expect(store.queue.events.first?.detail == .timers(input.timers))
        store.update(input: IslandInput(), now: now.addingTimeInterval(3))
        #expect(store.queue.events.isEmpty)
        #expect(store.lifecycle.phase == .idle)
    }

    @Test func transientSurvivesUpdatesButExpiresExactlyOnce() {
        let store = IslandStore()
        var input = IslandInput()
        store.update(input: input, now: now)
        input.clipboardEntry = IslandFixtures.clipboard()
        store.update(input: input, now: now.addingTimeInterval(1))
        #expect(store.queue.events.first?.since == now.addingTimeInterval(1))
        store.update(input: input, now: now.addingTimeInterval(2))
        #expect(store.queue.events.count == 1)
        #expect(store.queue.events.first?.since == now.addingTimeInterval(1))
        store.tick(now: now.addingTimeInterval(4.999))
        #expect(store.queue.events.count == 1)
        store.tick(now: now.addingTimeInterval(5))
        #expect(store.queue.events.isEmpty)
        #expect(store.lifecycle.phase == .idle)
        store.update(input: input, now: now.addingTimeInterval(6))
        #expect(store.queue.events.isEmpty)
    }

    @Test func latestCopyReplacesSameStableEventIDAndRestartsExpiry() {
        let store = IslandStore()
        var input = IslandInput()
        store.update(input: input, now: now)
        input.clipboardEntry = IslandFixtures.clipboard()
        store.update(input: input, now: now.addingTimeInterval(1))
        input.clipboardEntry = IslandFixtures.clipboard()
        store.update(input: input, now: now.addingTimeInterval(3))
        #expect(store.queue.events.count == 1)
        #expect(store.queue.events.first?.since == now.addingTimeInterval(3))
        store.tick(now: now.addingTimeInterval(5))
        #expect(store.queue.events.count == 1)
        store.tick(now: now.addingTimeInterval(7))
        #expect(store.queue.events.isEmpty)
    }

    @Test func networkWarningsSurviveRepeatedReadingsAndClearIndependently() {
        let store = IslandStore()
        var input = IslandInput()
        input.wifi = IslandFixtures.wifi
        input.vpn = IslandFixtures.vpn
        store.update(input: input, now: now)
        input.wifi = .notConnected
        input.vpn = IslandFixtures.vpnOff
        store.update(input: input, now: now.addingTimeInterval(1))
        store.update(input: input, now: now.addingTimeInterval(10))
        #expect(Set(store.queue.events.map(\.id)) == ["wifi", "vpn"])
        #expect(store.queue.events.allSatisfy { $0.since == now.addingTimeInterval(1) })
        input.wifi = IslandFixtures.wifi
        store.update(input: input, now: now.addingTimeInterval(11))
        #expect(store.queue.events.map(\.id) == ["vpn"])
        input.vpn = IslandFixtures.vpn
        store.update(input: input, now: now.addingTimeInterval(12))
        #expect(store.queue.events.isEmpty)
    }

    @Test func unknownNetworkReadingsDoNotInventRecovery() {
        let store = IslandStore()
        var input = IslandInput()
        input.wifi = IslandFixtures.wifi
        store.update(input: input, now: now)
        input.wifi = .off
        store.update(input: input, now: now.addingTimeInterval(1))
        input.wifi = nil
        store.update(input: input, now: now.addingTimeInterval(2))
        #expect(store.queue.events.first?.id == "wifi")
    }

    @Test func containerExitStaysUntilDismissedAndCanFireAgain() {
        let store = IslandStore()
        var input = IslandInput()
        input.docker = .containers([IslandFixtures.container(running: true)], context: nil)
        store.update(input: input, now: now)
        input.docker = .containers([IslandFixtures.container(running: false)], context: nil)
        store.update(input: input, now: now.addingTimeInterval(1))
        store.update(input: input, now: now.addingTimeInterval(100))
        store.tick(now: now.addingTimeInterval(200))
        #expect(store.queue.events.first?.id == "container:db")
        store.dismiss(id: "container:db")
        store.update(input: input, now: now.addingTimeInterval(201))
        #expect(store.queue.events.isEmpty)
        input.docker = .containers([IslandFixtures.container(running: true)], context: nil)
        store.update(input: input, now: now.addingTimeInterval(202))
        input.docker = .containers([IslandFixtures.container(running: false)], context: nil)
        store.update(input: input, now: now.addingTimeInterval(203))
        #expect(store.queue.events.count == 1)
    }

    @Test func dismissedOngoingEventWaitsForConditionToEndBeforeReturning() {
        let store = IslandStore()
        var input = IslandInput()
        input.isKeepingAwake = true
        input.keepAwakeEnds = now.addingTimeInterval(100)
        store.update(input: input, now: now)
        store.dismiss(id: "keepAwake")
        store.update(input: input, now: now.addingTimeInterval(1))
        #expect(store.queue.events.isEmpty)
        input.isKeepingAwake = false
        store.update(input: input, now: now.addingTimeInterval(2))
        input.isKeepingAwake = true
        store.update(input: input, now: now.addingTimeInterval(3))
        #expect(store.queue.events.first?.id == "keepAwake")
    }

    @Test func dismissingNetworkLossDoesNotReappearUntilAnotherLoss() {
        let store = IslandStore()
        var input = IslandInput()
        input.vpn = IslandFixtures.vpn
        store.update(input: input, now: now)
        input.vpn = IslandFixtures.vpnOff
        store.update(input: input, now: now.addingTimeInterval(1))
        store.dismiss(id: "vpn")
        store.update(input: input, now: now.addingTimeInterval(2))
        #expect(store.queue.events.isEmpty)
        input.vpn = IslandFixtures.vpn
        store.update(input: input, now: now.addingTimeInterval(3))
        input.vpn = IslandFixtures.vpnOff
        store.update(input: input, now: now.addingTimeInterval(4))
        #expect(store.queue.events.first?.id == "vpn")
    }

    @Test func pagingClampsAfterQueueChanges() {
        let store = IslandStore()
        var input = IslandInput()
        input.calendarEvents = [IslandFixtures.event(startsIn: 10, endsIn: 100)]
        input.timers = [CountdownTimer(title: "Tea", duration: 60, start: now)]
        store.update(input: input, now: now)
        store.showPage(50)
        #expect(store.page == 1)
        store.dismiss(id: "timers")
        #expect(store.page == 0)
        store.showPage(-1)
        #expect(store.page == 0)
        store.dismiss(id: "meeting:event")
        #expect(store.page == 0)
        #expect(store.queue.events.isEmpty)
    }

    @Test func queueExpiryWhileExpandedKeepsCardUntilCollapse() {
        let store = IslandStore()
        store.update(input: IslandInput(), now: now)
        var input = IslandInput()
        input.clipboardEntry = IslandFixtures.clipboard()
        store.update(input: input, now: now)
        store.lifecycle.clicked()
        #expect(store.lifecycle.phase == .expanded)
        store.tick(now: now.addingTimeInterval(4))
        #expect(store.queue.events.isEmpty)
        #expect(store.lifecycle.phase == .expanded)
        store.lifecycle.pointerExited(at: now.addingTimeInterval(4))
        store.tick(now: now.addingTimeInterval(5))
        #expect(store.lifecycle.phase == .idle)
    }

    @Test func tickDrivesHoverExpansionAndExitCollapse() {
        let store = IslandStore(hoverToExpand: true)
        var input = IslandInput()
        input.timers = [CountdownTimer(title: "Tea", duration: 60, start: now)]
        store.update(input: input, now: now)
        store.lifecycle.pointerEntered(at: now)
        store.tick(now: now.addingTimeInterval(0.3))
        #expect(store.lifecycle.phase == .expanded)
        store.lifecycle.pointerExited(at: now.addingTimeInterval(0.4))
        store.tick(now: now.addingTimeInterval(1.4))
        #expect(store.lifecycle.phase == .compact)
    }

    @Test func expiredTransitionsAreAlsoRemovedByUpdate() {
        let store = IslandStore()
        var input = IslandInput()
        input.battery = IslandFixtures.battery(onAC: false)
        store.update(input: input, now: now)
        input.battery = IslandFixtures.battery(onAC: true)
        store.update(input: input, now: now.addingTimeInterval(1))
        #expect(store.queue.events.first?.kind == .charging)
        store.update(input: input, now: now.addingTimeInterval(5))
        #expect(store.queue.events.isEmpty)
    }
}

@MainActor
struct IslandContextTests {
    private let now = IslandFixtures.now

    @Test func firstSnapshotCarriesRelatedReadings() {
        var input = IslandInput()
        input.calendarEvents = [
            IslandFixtures.event("current", startsIn: -100, endsIn: 100),
            IslandFixtures.event("next", startsIn: 3600, endsIn: 7200),
        ]
        input.sensors = SensorSample(readings: [], fans: [
            FanReading(id: 0, rpm: 5600, minimum: 1000, maximum: 6000),
        ])
        input.artwork = Data([1, 2, 3])
        input.outputDevice = "Speakers"
        input.keepAwakeIncludesDisplay = true
        let context = IslandEventBuilder.events(current: input, previous: nil, now: now).first?.context
        #expect(context?.nextEvent?.id == "next")
        #expect(context?.fanRPM == 5600)
        #expect(context?.artwork == input.artwork)
        #expect(context?.outputDevice == "Speakers")
        #expect(context?.keepAwakeIncludesDisplay == true)
    }

    @Test func persistentAlertRefreshesContextWithoutRestartingItsLifetime() {
        let store = IslandStore()
        var input = IslandInput()
        input.wifi = IslandFixtures.wifi
        store.update(input: input, now: now)
        input.wifi = .notConnected
        input.ping = .timeout
        store.update(input: input, now: now.addingTimeInterval(1))
        input.ping = .reply(milliseconds: 18)
        input.previousPing = .timeout
        input.vpn = IslandFixtures.vpnOff
        store.update(input: input, now: now.addingTimeInterval(2))
        let event = store.queue.events.first { $0.id == "wifi" }
        #expect(event?.since == now.addingTimeInterval(1))
        #expect(event?.context.ping == .reply(milliseconds: 18))
        #expect(event?.context.previousPing == .timeout)
        #expect(event?.context.vpn == input.vpn)
    }

    @Test func pinningRefreshesTheCopyWithoutExtendingItsExpiry() {
        let store = IslandStore()
        store.update(input: IslandInput(), now: now)
        var input = IslandInput()
        input.clipboardEntry = IslandFixtures.clipboard()
        store.update(input: input, now: now)
        input.clipboardEntry?.isPinned = true
        store.update(input: input, now: now.addingTimeInterval(1))
        #expect(store.queue.events.first?.detail == input.clipboardEntry.map(IslandDetail.copied))
        #expect(store.queue.events.first?.expires == now.addingTimeInterval(4))
    }

    @Test func clipboardPreviewSurvivesAnUnavailableReadingUntilExpiry() {
        let store = IslandStore()
        store.update(input: IslandInput(), now: now)
        var input = IslandInput()
        input.clipboardEntry = IslandFixtures.clipboard()
        input.clipboardPreview = Data([1, 2, 3])
        input.clipboardImageURL = URL(fileURLWithPath: "/tmp/example.png")
        store.update(input: input, now: now)
        store.update(input: IslandInput(), now: now.addingTimeInterval(1))
        #expect(store.queue.events.first?.context.clipboardPreview == input.clipboardPreview)
        #expect(store.queue.events.first?.context.clipboardImageURL == input.clipboardImageURL)
        store.tick(now: now.addingTimeInterval(4))
        #expect(store.queue.events.isEmpty)
    }
}
