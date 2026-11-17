import Foundation
@testable import GlassWorkCore
import Testing

struct SleepHistoryTests {
    private let boot = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ minutes: Double) -> Date {
        boot.addingTimeInterval(minutes * 60)
    }

    @Test func sessionsRunFromBootThroughEachWake() {
        var history = SleepHistory(boot: boot)
        history.record(.sleep, at: at(30))
        history.record(.wake, at: at(60))
        history.record(.sleep, at: at(90))
        history.record(.wake, at: at(100))
        let sessions = history.sessions(limit: 5)
        #expect(sessions == [
            AwakeSession(start: at(100), end: nil),
            AwakeSession(start: at(60), end: at(90)),
            AwakeSession(start: boot, end: at(30)),
        ])
        #expect(history.sleepCount == 2)
        #expect(history.lastSleep == at(90))
        #expect(history.lastWake == at(100))
        #expect(sessions[1].duration(now: at(200)) == 1800)
        #expect(sessions[0].duration(now: at(110)) == 600)
    }

    @Test func aSleepingMacHasNoOpenSession() {
        var history = SleepHistory(boot: boot)
        history.record(.sleep, at: at(10))
        #expect(history.sessions(limit: 5) == [AwakeSession(start: boot, end: at(10))])
    }

    @Test func aFreshBootHasOneOpenSession() {
        let history = SleepHistory(boot: boot)
        #expect(history.sessions(limit: 5) == [AwakeSession(start: boot, end: nil)])
        #expect(history.lastSleep == nil)
        #expect(history.lastWake == nil)
    }

    @Test func repeatedEventsAreNotCounted() {
        var history = SleepHistory(boot: boot)
        history.record(.wake, at: at(1))
        history.record(.sleep, at: at(5))
        history.record(.sleep, at: at(6))
        #expect(history.sleepCount == 1)
        #expect(history.events.count == 1)
    }

    @Test func theLimitKeepsTheNewestSessions() {
        var history = SleepHistory(boot: boot)
        for index in 0 ..< 10 {
            history.record(.sleep, at: at(Double(index) * 20 + 10))
            history.record(.wake, at: at(Double(index) * 20 + 15))
        }
        let sessions = history.sessions(limit: 5)
        #expect(sessions.count == 5)
        #expect(sessions.first?.start == at(195))
        #expect(history.sleepCount == 10)
    }

    @Test func theEventListIsCappedButTheCountIsNot() {
        var history = SleepHistory(boot: boot)
        for index in 0 ..< 60 {
            history.record(.sleep, at: at(Double(index) * 10 + 5))
            history.record(.wake, at: at(Double(index) * 10 + 8))
        }
        #expect(history.events.count == SleepHistory.capacity)
        #expect(history.sleepCount == 60)
        // The start of the oldest kept session is unknown, so none is invented from the boot time.
        #expect(history.sessions(limit: 100).allSatisfy { $0.start > boot })
    }

    @Test func aSavedHistoryOfTheSameBootIsKept() {
        var saved = SleepHistory(boot: boot)
        saved.record(.sleep, at: at(30))
        let restored = SleepHistory.restored(saved, boot: boot.addingTimeInterval(3))
        #expect(restored.sleepCount == 1)
    }

    @Test func aSavedHistoryOfAnotherBootIsDropped() {
        var saved = SleepHistory(boot: boot)
        saved.record(.sleep, at: at(30))
        let restored = SleepHistory.restored(saved, boot: at(600))
        #expect(restored.sleepCount == 0)
        #expect(restored.events.isEmpty)
        #expect(SleepHistory.restored(nil, boot: boot).events.isEmpty)
    }

    @Test func historyRoundTripsThroughJSON() throws {
        var history = SleepHistory(boot: boot)
        history.record(.sleep, at: at(30))
        history.record(.wake, at: at(45))
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(SleepHistory.self, from: data) == history)
    }

    @MainActor
    @Test func theLogSurvivesARestart() {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkSleep-\(UUID().uuidString)/SleepHistory.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = SleepLog(url: url, boot: boot)
        first.load()
        first.record(.sleep, at: at(30))
        first.record(.wake, at: at(40))
        let second = SleepLog(url: url, boot: boot)
        second.load()
        #expect(second.history.sleepCount == 1)
        #expect(second.history.lastWake == at(40))
        let afterReboot = SleepLog(url: url, boot: at(900))
        afterReboot.load()
        #expect(afterReboot.history.events.isEmpty)
    }
}
