import Foundation
@testable import GlassWorkCore
import Testing

struct PomodoroTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// 2026-11-04 09:00 UTC.
    private let start = Date(timeIntervalSince1970: 1_793_750_400 + 9 * 3600)

    private func running() -> PomodoroSession {
        var session = PomodoroSession()
        session.start(at: start)
        return session
    }

    @Test func idleHasNoState() {
        #expect(PomodoroSession().state(at: start) == nil)
        #expect(!PomodoroSession().isRunning)
    }

    @Test func firstFocusRound() throws {
        let state = try #require(running().state(at: start.addingTimeInterval(10 * 60)))
        #expect(state.phase == .focus)
        #expect(state.round == 1)
        #expect(state.remaining(at: start.addingTimeInterval(10 * 60)) == 15 * 60)
        #expect(state.completedFocus == 0)
        #expect(state.share(at: start.addingTimeInterval(10 * 60)) == 0.4)
    }

    @Test func shortBreakFollowsFocus() throws {
        let state = try #require(running().state(at: start.addingTimeInterval(27 * 60)))
        #expect(state.phase == .shortBreak)
        #expect(state.duration == 5 * 60)
        #expect(state.completedFocus == 1)
    }

    @Test func longBreakAfterTheFourthRound() throws {
        // Four 25-minute rounds with three 5-minute breaks, then the long break.
        let atLongBreak = start.addingTimeInterval((4 * 25 + 3 * 5 + 2) * 60)
        let state = try #require(running().state(at: atLongBreak))
        #expect(state.phase == .longBreak)
        #expect(state.round == 4)
        #expect(state.duration == 15 * 60)
        let after = try #require(running().state(at: atLongBreak.addingTimeInterval(15 * 60)))
        #expect(after.phase == .focus)
        #expect(after.round == 1)
        #expect(after.completedFocus == 4)
    }

    @Test func upcomingPhases() {
        let list = running().upcoming(3, at: start.addingTimeInterval(60))
        #expect(list.map(\.phase) == [.shortBreak, .focus, .shortBreak])
        #expect(list.first?.phaseStart == start.addingTimeInterval(25 * 60))
    }

    @Test func stoppingKeepsTheFinishedRounds() {
        var session = running()
        // Two rounds are done after 25 + 5 + 25 minutes.
        session.stop(at: start.addingTimeInterval(56 * 60), calendar: calendar)
        #expect(!session.isRunning)
        #expect(session.completedToday(at: start.addingTimeInterval(3600), calendar: calendar) == 2)
        #expect(session.state(at: start) == nil)
    }

    @Test func countsARunStillGoing() {
        let session = running()
        #expect(session.completedToday(at: start.addingTimeInterval(61 * 60), calendar: calendar) == 2)
        let recent = session.recentDays(3, at: start.addingTimeInterval(61 * 60), calendar: calendar)
        #expect(recent.map(\.count) == [0, 0, 2])
    }

    @Test func oldHistoryIsDropped() {
        var session = PomodoroSession()
        for day in 1 ... 20 {
            session.history[String(format: "2026-10-%02d", day)] = 1
        }
        session.start(at: start)
        session.stop(at: start.addingTimeInterval(30 * 60), calendar: calendar)
        #expect(session.history.count == PomodoroSession.keepDays)
    }

    @Test func dataSavedBeforePomodoroStillLoads() throws {
        let old = #"{"note":"keep me","timers":[],"dates":[],"stopwatch":{"accumulated":0},"cities":[],"colors":[]}"#
        let decoded = try JSONDecoder().decode(EverydayData.self, from: Data(old.utf8))
        #expect(decoded.note == "keep me")
        #expect(decoded.pomodoro == nil)
    }
}
