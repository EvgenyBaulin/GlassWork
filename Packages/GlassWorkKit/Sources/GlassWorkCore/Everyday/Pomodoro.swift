import Foundation

public enum PomodoroPhase: String, Codable, Sendable, Equatable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool {
        self != .focus
    }
}

/// Where a running Pomodoro stands at one moment.
public struct PomodoroState: Sendable, Equatable {
    public let phase: PomodoroPhase
    /// Which focus round of the set this is, from 1.
    public let round: Int
    public let phaseStart: Date
    public let phaseEnd: Date
    /// Focus rounds finished since the run started.
    public let completedFocus: Int

    public var duration: TimeInterval {
        phaseEnd.timeIntervalSince(phaseStart)
    }

    public func remaining(at date: Date) -> TimeInterval {
        max(phaseEnd.timeIntervalSince(date), 0)
    }

    public func share(at date: Date) -> Double {
        min(max(date.timeIntervalSince(phaseStart) / max(duration, 1), 0), 1)
    }
}

/// A Pomodoro run: focus, short break, focus, and a long break after every few rounds, until stopped.
/// Only the start is stored, so the state at any moment is computed and widgets never go stale.
public struct PomodoroSession: Codable, Sendable, Equatable {
    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var roundsPerSet = 4
    public var startedAt: Date?
    /// Focus rounds finished per day, from runs that were stopped. Kept for two weeks.
    public var history: [String: Int] = [:]

    public static let keepDays = 14

    public init() {}

    public var isRunning: Bool {
        startedAt != nil
    }

    private var focusLength: TimeInterval {
        Double(max(focusMinutes, 1)) * 60
    }

    private func breakLength(after round: Int) -> (PomodoroPhase, TimeInterval) {
        let perSet = max(roundsPerSet, 1)
        return round % perSet == 0
            ? (.longBreak, Double(max(longBreakMinutes, 1)) * 60)
            : (.shortBreak, Double(max(shortBreakMinutes, 1)) * 60)
    }

    /// The phase at `date`; nil when no run is under way.
    public func state(at date: Date) -> PomodoroState? {
        guard let startedAt, date >= startedAt else { return nil }
        var cursor = startedAt
        var round = 1
        while true {
            let focusEnd = cursor.addingTimeInterval(focusLength)
            if date < focusEnd {
                let inSet = (round - 1) % max(roundsPerSet, 1) + 1
                return PomodoroState(
                    phase: .focus, round: inSet, phaseStart: cursor, phaseEnd: focusEnd, completedFocus: round - 1
                )
            }
            let (phase, length) = breakLength(after: round)
            let breakEnd = focusEnd.addingTimeInterval(length)
            if date < breakEnd {
                let inSet = (round - 1) % max(roundsPerSet, 1) + 1
                return PomodoroState(
                    phase: phase, round: inSet, phaseStart: focusEnd, phaseEnd: breakEnd, completedFocus: round
                )
            }
            cursor = breakEnd
            round += 1
        }
    }

    /// The phases that follow the one under way at `date`.
    public func upcoming(_ count: Int, at date: Date) -> [PomodoroState] {
        var result: [PomodoroState] = []
        var cursor = state(at: date)
        while result.count < count, let current = cursor, let next = state(at: current.phaseEnd) {
            result.append(next)
            cursor = next
        }
        return result
    }

    /// The ends of the focus rounds finished by `date`.
    private func focusEnds(until date: Date) -> [Date] {
        guard let startedAt, date >= startedAt else { return [] }
        var ends: [Date] = []
        var cursor = startedAt
        var round = 1
        while true {
            let focusEnd = cursor.addingTimeInterval(focusLength)
            guard focusEnd <= date else { return ends }
            ends.append(focusEnd)
            cursor = focusEnd.addingTimeInterval(breakLength(after: round).1)
            round += 1
        }
    }

    public mutating func start(at date: Date) {
        startedAt = date
    }

    /// Ends the run and keeps the focus rounds it finished.
    public mutating func stop(at date: Date, calendar: Calendar = .current) {
        for end in focusEnds(until: date) {
            history[ScreenTimeLog.dayKey(end, calendar: calendar), default: 0] += 1
        }
        startedAt = nil
        let keep = history.keys.sorted().suffix(Self.keepDays)
        history = history.filter { keep.contains($0.key) }
    }

    /// Focus rounds finished on the day of `date`, including a run still going.
    public func completedToday(at date: Date, calendar: Calendar = .current) -> Int {
        let key = ScreenTimeLog.dayKey(date, calendar: calendar)
        let running = focusEnds(until: date).filter { ScreenTimeLog.dayKey($0, calendar: calendar) == key }.count
        return history[key, default: 0] + running
    }

    /// Finished rounds per day for the last `days` days, oldest first, including a run still going.
    public func recentDays(_ days: Int, at date: Date, calendar: Calendar = .current) -> [(date: Date, count: Int)] {
        let today = calendar.startOfDay(for: date)
        var running: [String: Int] = [:]
        for end in focusEnds(until: date) {
            running[ScreenTimeLog.dayKey(end, calendar: calendar), default: 0] += 1
        }
        return (0 ..< days).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let key = ScreenTimeLog.dayKey(day, calendar: calendar)
            return (day, history[key, default: 0] + running[key, default: 0])
        }
    }
}
