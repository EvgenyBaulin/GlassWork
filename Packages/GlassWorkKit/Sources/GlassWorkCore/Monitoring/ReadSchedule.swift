import Foundation

/// What the loop has to wait for: reads that happen on every tick, and the dates other reads fall due.
struct ReadPlan: Equatable {
    var everyTick = false
    var dates: [Date] = []
}

/// When the sampler loop wakes next. Everything here is a pure function of dates, so tests never wait.
enum ReadSchedule {
    /// Half a second of slack, as `SampleKind.isDue` has, so a 5 s pace does not slip to the tick after next.
    static let tolerance: TimeInterval = 0.5
    /// A wake that lands a hair before a due date would cost another whole sleep.
    static let slack: TimeInterval = 0.05
    static let shortestSleep: TimeInterval = 1
    static let longestSleep: TimeInterval = 30
    /// Battery and disk space change with events; this is the net for what the events do not cover (time
    /// remaining, temperature, cycle count, free space).
    static let backstop: TimeInterval = 60

    /// When a metric last read at `last` falls due, or now if it was never read or reads on every tick.
    static func dueDate(last: Date?, pace: TimeInterval?, now: Date) -> Date {
        guard let last, let pace, last <= now else { return now }
        return last.addingTimeInterval(pace - tolerance)
    }

    /// True when a read is wanted: an event came in, nothing was read yet, or the interval has passed.
    static func isDue(last: Date?, interval: TimeInterval, event: Bool, at now: Date) -> Bool {
        event || dueDate(last: last, pace: interval, now: now) <= now
    }

    /// Battery and volumes read at the interval a panel shows while one is open, and on the backstop otherwise.
    static func eventDrivenInterval(panelOpen: Bool, panelInterval: TimeInterval) -> TimeInterval {
        panelOpen ? panelInterval : backstop
    }

    /// The date for a read that events normally trigger. An event that already came in makes it due now.
    static func eventDrivenDate(last: Date?, interval: TimeInterval, event: Bool, now: Date) -> Date {
        event ? now : dueDate(last: last, pace: interval, now: now)
    }

    /// The next wake: the earliest due date, but not sooner than a second (a tick that finds nothing due is wasted
    /// work) and not later than 30 s (stores that tick with the loop, such as weather, only need that much).
    static func nextWake(now: Date, tickInterval: TimeInterval, plan: ReadPlan) -> Date {
        var candidates = plan.dates.map { $0.addingTimeInterval(slack) }
        if plan.everyTick {
            candidates.append(now.addingTimeInterval(tickInterval))
        }
        let earliest = candidates.min() ?? now.addingTimeInterval(longestSleep)
        let lower = now.addingTimeInterval(min(shortestSleep, tickInterval))
        let upper = now.addingTimeInterval(longestSleep)
        return min(max(earliest, lower), upper)
    }
}

/// Sleeps in the sampler loop and can be woken early. A wake that comes while the loop is busy is kept for the
/// next sleep, so an event during a read is not lost.
@MainActor
final class LoopSleeper {
    private var sleeper: Task<Void, Never>?
    private var isWoken = false

    func sleep(for seconds: TimeInterval) async {
        if isWoken {
            isWoken = false
            return
        }
        let task = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(seconds)) }
        sleeper = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        sleeper = nil
        isWoken = false
    }

    func wake() {
        isWoken = true
        sleeper?.cancel()
    }

    func reset() {
        isWoken = false
    }
}
