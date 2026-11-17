import Foundation

public extension ModuleID {
    /// The modules a shortcut can open a panel for.
    static var shortcutModules: [ModuleID] {
        allCases.filter { !$0.isDockOnly }
    }
}

/// The Counter widget: a number and a title, kept in the options of its module.
public struct CounterState: Sendable, Equatable {
    public static let valueKey = "counter.value"
    public static let titleKey = "counter.title"
    public static let countsOnClickKey = "counter.countsOnClick"
    /// Far beyond what anyone counts, and short enough for a tile.
    public static let limit = 999_999
    public static let maxTitleLength = 24

    public var value = 0
    public var title = ""
    /// A click on the tile adds one, instead of opening the card.
    public var countsOnClick = false

    public init() {}

    public init(options: [String: String]) {
        value = Self.clamp(options.number(Self.valueKey, default: 0))
        title = options[Self.titleKey] ?? ""
        countsOnClick = options.flag(Self.countsOnClickKey, default: false)
    }

    public mutating func increment() {
        value = Self.clamp(value + 1)
    }

    public mutating func decrement() {
        value = Self.clamp(value - 1)
    }

    public mutating func reset() {
        value = 0
    }

    /// Defaults are not stored, so an untouched counter leaves the options empty.
    public func write(to options: inout [String: String]) {
        options[Self.valueKey] = value == 0 ? nil : String(value)
        let trimmed = String(title.prefix(Self.maxTitleLength))
        options[Self.titleKey] = trimmed.isEmpty ? nil : trimmed
        options[Self.countsOnClickKey] = countsOnClick ? "true" : nil
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, -limit), limit)
    }
}

public extension AppSettings {
    mutating func updateCounter(_ change: (inout CounterState) -> Void) {
        update(.counter) { module in
            var state = CounterState(options: module.options)
            change(&state)
            state.write(to: &module.options)
        }
    }
}

public enum BreathingPhase: String, Sendable, Equatable {
    case inhale, hold, exhale
}

/// One breath: in, hold, out. Times in seconds.
public struct BreathingCycle: Sendable, Equatable {
    public struct Moment: Sendable, Equatable {
        public let phase: BreathingPhase
        /// Whole seconds left in the phase, counting down to 1.
        public let secondsLeft: Int
        /// How full the lungs are, 0 to 1: the circle's size.
        public let fullness: Double
    }

    public var inhale = 4.0
    public var hold = 4.0
    public var exhale = 6.0

    public init() {}

    public var length: TimeInterval {
        inhale + hold + exhale
    }

    public func moment(at elapsed: TimeInterval) -> Moment {
        let time = max(elapsed, 0).truncatingRemainder(dividingBy: length)
        if time < inhale {
            return Moment(phase: .inhale, secondsLeft: Self.left(inhale - time), fullness: Self.ease(time / inhale))
        }
        if time < inhale + hold {
            return Moment(phase: .hold, secondsLeft: Self.left(inhale + hold - time), fullness: 1)
        }
        let out = time - inhale - hold
        return Moment(phase: .exhale, secondsLeft: Self.left(exhale - out), fullness: 1 - Self.ease(out / exhale))
    }

    private static func left(_ seconds: Double) -> Int {
        max(Int(seconds.rounded(.up)), 1)
    }

    /// Smooth start and end, so the circle does not jerk at a phase change.
    private static func ease(_ fraction: Double) -> Double {
        let clamped = min(max(fraction, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// A guided session of a chosen length.
public struct BreathingSession: Sendable, Equatable {
    public static let minutesKey = "breathe.minutes"
    public static let choices = [1, 3, 5]
    public static let defaultMinutes = 3

    public var cycle = BreathingCycle()
    public var minutes: Int

    public init(minutes: Int = defaultMinutes) {
        self.minutes = Self.choices.contains(minutes) ? minutes : Self.defaultMinutes
    }

    public init(options: [String: String]) {
        self.init(minutes: options.number(Self.minutesKey, default: Self.defaultMinutes))
    }

    public var duration: TimeInterval {
        Double(minutes) * 60
    }

    /// Nil once the time is up.
    public func moment(at elapsed: TimeInterval) -> BreathingCycle.Moment? {
        elapsed < duration ? cycle.moment(at: elapsed) : nil
    }

    public func remaining(at elapsed: TimeInterval) -> TimeInterval {
        max(duration - max(elapsed, 0), 0)
    }

    /// The slow swell of the tile while no session runs, 0 to 1 over ten seconds.
    public static func idleFullness(at date: Date) -> Double {
        let seconds = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10)
        return (1 - cos(seconds / 10 * 2 * .pi)) / 2
    }
}

/// What the Screen Time widget of the Dock says about today and the week.
public struct ScreenTimeSummary: Sendable, Equatable {
    public struct App: Sendable, Equatable {
        public let name: String
        public let seconds: Double
    }

    public let today: Double
    public let week: ScreenWeekStats
    public let topApps: [App]
    public let breaks: ScreenBreakStats

    public init(log: ScreenTimeLog, at date: Date, topLimit: Int = 3, calendar: Calendar = .current) {
        let day = log.today(date, calendar: calendar)
        today = day?.total ?? 0
        week = ScreenWeekStats(log: log, at: date, calendar: calendar)
        topApps = day.map { log.topApps(in: $0, limit: topLimit).map { App(name: $0.app, seconds: $0.seconds) } } ?? []
        breaks = ScreenBreakStats(day: day, at: date)
    }

    public var hasData: Bool {
        today > 0
    }

    /// The tile's figure, with a dash while nothing is recorded.
    public var tileText: String {
        hasData ? CompactDuration.format(today) : "–"
    }
}
