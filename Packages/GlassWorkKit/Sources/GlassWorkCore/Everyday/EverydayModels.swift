import Foundation

/// A countdown timer. Running timers store their end, paused ones what was left.
public struct CountdownTimer: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var duration: TimeInterval
    public var endDate: Date?
    public var pausedRemaining: TimeInterval?

    public init(title: String, duration: TimeInterval, start: Date) {
        self.title = title
        self.duration = duration
        endDate = start.addingTimeInterval(duration)
    }

    public var isPaused: Bool {
        pausedRemaining != nil
    }

    public func remaining(at date: Date) -> TimeInterval {
        if let pausedRemaining {
            return pausedRemaining
        }
        return max(endDate?.timeIntervalSince(date) ?? 0, 0)
    }

    public func isFinished(at date: Date) -> Bool {
        !isPaused && remaining(at: date) <= 0
    }

    public mutating func togglePause(at date: Date) {
        if let left = pausedRemaining {
            pausedRemaining = nil
            endDate = date.addingTimeInterval(left)
        } else {
            pausedRemaining = remaining(at: date)
            endDate = nil
        }
    }
}

/// A date to count down to.
public struct ImportantDate: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var title: String
    public var date: Date

    public init(title: String, date: Date) {
        self.title = title
        self.date = date
    }

    /// Calendar days left; today counts as zero.
    public func daysLeft(from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
    }
}

public struct Stopwatch: Codable, Sendable, Equatable {
    public var accumulated: TimeInterval = 0
    public var startedAt: Date?

    public init() {}

    public var isRunning: Bool {
        startedAt != nil
    }

    public func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    public mutating func toggle(at date: Date) {
        if let startedAt {
            accumulated += date.timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = date
        }
    }

    public mutating func reset() {
        self = Stopwatch()
    }
}

/// A place in the world clocks list.
public struct WorldCity: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        timeZone
    }

    public var name: String
    public var timeZone: String

    public init(name: String, timeZone: String) {
        self.name = name
        self.timeZone = timeZone
    }
}

/// Everything the small everyday modules keep. Shared with widgets through the App Group.
public struct EverydayData: Codable, Sendable, Equatable {
    public var note = ""
    public var timers: [CountdownTimer] = []
    public var dates: [ImportantDate] = []
    public var stopwatch = Stopwatch()
    public var cities: [WorldCity] = []
    public var colors: [String] = []
    /// Optional so data saved before Pomodoro existed still decodes.
    public var pomodoro: PomodoroSession?

    public init() {}

    public static let key = "everyday"
    public static let colorLimit = 12

    public mutating func addColor(_ hex: String, limit: Int = EverydayData.colorLimit) {
        colors.removeAll { $0 == hex }
        colors.insert(hex, at: 0)
        colors = Array(colors.prefix(limit))
    }

    /// Soonest first; dates already gone stay at the end.
    public func sortedDates(from now: Date) -> [ImportantDate] {
        dates.sorted { lhs, rhs in
            let left = lhs.daysLeft(from: now)
            let right = rhs.daysLeft(from: now)
            if (left < 0) != (right < 0) {
                return left >= 0
            }
            return left < right
        }
    }
}

public extension TimeInterval {
    /// "12:30" or "1:02:03".
    var clockText: String {
        let total = Int(rounded(.up))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
