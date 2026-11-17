import Foundation
@testable import GlassWorkCore
import Testing

struct PingOutageTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let reply = PingOutcome.reply(milliseconds: 8)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func aSingleMissIsNotAnOutage() {
        var tracker = PingOutageTracker()
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(0)) == nil)
        #expect(tracker.update(host: "h", outcome: reply, at: at(10)) == nil)
    }

    @Test func downIsAnnouncedAfterThirtySecondsOfMisses() {
        var tracker = PingOutageTracker()
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(0)) == nil)
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(29)) == nil)
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(30)) == .down(host: "h"))
    }

    @Test func oneAnnouncementPerOutage() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: .timeout, at: at(30))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(60)) == nil)
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(90)) == nil)
    }

    @Test func recoveryReportsHowLongItWasDown() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: .timeout, at: at(30))
        let event = tracker.update(host: "h", outcome: reply, at: at(120))
        #expect(event == .recovered(host: "h", downFor: 120))
        #expect(tracker.update(host: "h", outcome: reply, at: at(150)) == nil)
    }

    @Test func aSecondOutageIsAnnouncedAgain() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: .timeout, at: at(30))
        _ = tracker.update(host: "h", outcome: reply, at: at(60))
        _ = tracker.update(host: "h", outcome: .timeout, at: at(90))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(120)) == .down(host: "h"))
    }

    @Test func aReplyBetweenMissesRestartsTheCount() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: reply, at: at(20))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(40)) == nil)
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(60)) == nil)
    }

    @Test func theMacBeingOfflineIsNotTheHostBeingDown() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: .offline, at: at(20))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(40)) == nil)
    }

    @Test func anOutageAlreadyAnnouncedSurvivesAnOfflineMoment() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "h", outcome: .timeout, at: at(30))
        #expect(tracker.update(host: "h", outcome: .offline, at: at(60)) == nil)
        #expect(tracker.update(host: "h", outcome: reply, at: at(90)) == .recovered(host: "h", downFor: 90))
    }

    @Test func theSameEchoFedTwiceCountsOnce() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "h", outcome: .timeout, at: at(0))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(30)) == .down(host: "h"))
        #expect(tracker.update(host: "h", outcome: .timeout, at: at(30)) == nil)
    }

    @Test func anotherHostStartsFresh() {
        var tracker = PingOutageTracker()
        _ = tracker.update(host: "a", outcome: .timeout, at: at(0))
        _ = tracker.update(host: "a", outcome: .timeout, at: at(30))
        #expect(tracker.update(host: "b", outcome: reply, at: at(60)) == nil)
    }
}
