import Foundation
@testable import GlassWorkCore
import Testing

struct AIUsageAlertTrackerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(
        _ tool: AITool = .codex,
        used: Double,
        kind: AIWindow.Kind = .fiveHour,
        resets: TimeInterval? = 3600
    ) -> AIUsageReading {
        let window = AIWindow(kind: kind, used: used, resetsAt: resets.map { now.addingTimeInterval($0) })
        return AIUsageReading(tools: [AIToolUsage(tool: tool, windows: [window])], readAt: now)
    }

    @Test func staysQuietBelowTheLevel() {
        var tracker = AIUsageAlertTracker()
        #expect(tracker.update(reading(used: 0.84), warnShare: 0.85, now: now).isEmpty)
    }

    @Test func firesOnceWhenTheLevelIsReached() {
        var tracker = AIUsageAlertTracker()
        let fired = tracker.update(reading(used: 0.85), warnShare: 0.85, now: now)
        #expect(fired.count == 1)
        #expect(fired.first?.tool == .codex)
        #expect(fired.first?.kind == .fiveHour)
        #expect(tracker.update(reading(used: 0.9), warnShare: 0.85, now: now.addingTimeInterval(60)).isEmpty)
    }

    @Test func aDipAndReturnInTheSamePeriodStaysQuiet() {
        var tracker = AIUsageAlertTracker()
        _ = tracker.update(reading(used: 0.9), warnShare: 0.85, now: now)
        #expect(tracker.update(reading(used: 0.5), warnShare: 0.85, now: now).isEmpty)
        #expect(tracker.update(reading(used: 0.95), warnShare: 0.85, now: now).isEmpty)
    }

    @Test func aSlightlyDifferentResetTimeIsTheSamePeriod() {
        var tracker = AIUsageAlertTracker()
        _ = tracker.update(reading(used: 0.9, resets: 3600), warnShare: 0.85, now: now)
        #expect(tracker.update(reading(used: 0.9, resets: 3630), warnShare: 0.85, now: now).isEmpty)
    }

    @Test func aNewPeriodFiresAgain() {
        var tracker = AIUsageAlertTracker()
        _ = tracker.update(reading(used: 0.9, resets: 3600), warnShare: 0.85, now: now)
        let later = now.addingTimeInterval(5 * 3600)
        let next = reading(used: 0.9, resets: 5 * 3600 + 3600)
        #expect(tracker.update(next, warnShare: 0.85, now: later).count == 1)
    }

    @Test func eachToolAndWindowHasItsOwnNotification() {
        var tracker = AIUsageAlertTracker()
        #expect(tracker.update(reading(.codex, used: 0.9), warnShare: 0.85, now: now).count == 1)
        #expect(tracker.update(reading(.claudeCode, used: 0.9), warnShare: 0.85, now: now).count == 1)
        #expect(tracker.update(reading(.codex, used: 0.9, kind: .week), warnShare: 0.85, now: now).count == 1)
        #expect(tracker.update(reading(.codex, used: 0.9), warnShare: 0.85, now: now).isEmpty)
    }

    @Test func aWindowPastItsResetCountsAsEmpty() {
        var tracker = AIUsageAlertTracker()
        let expired = reading(used: 0.99, resets: -60)
        #expect(tracker.update(expired, warnShare: 0.85, now: now).isEmpty)
    }

    @Test func withoutAResetTimeTheValueFallingBackStartsANewPeriod() {
        var tracker = AIUsageAlertTracker()
        #expect(tracker.update(reading(used: 0.9, resets: nil), warnShare: 0.85, now: now).count == 1)
        #expect(tracker.update(reading(used: 0.95, resets: nil), warnShare: 0.85, now: now).isEmpty)
        #expect(tracker.update(reading(used: 0.1, resets: nil), warnShare: 0.85, now: now).isEmpty)
        #expect(tracker.update(reading(used: 0.9, resets: nil), warnShare: 0.85, now: now).count == 1)
    }

    @Test func notifyingIsOnByDefault() {
        #expect(AIUsageOption.notifies([:]))
        #expect(!AIUsageOption.notifies([AIUsageOption.notifyAtWarning: "false"]))
    }
}
