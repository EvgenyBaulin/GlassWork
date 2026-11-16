import Foundation

/// One moment the Mac went to sleep or woke up.
public struct SleepEvent: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case sleep, wake
    }

    public let kind: Kind
    public let date: Date

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }
}

/// A stretch of the Mac being awake. `end` is nil for the one still going.
public struct AwakeSession: Sendable, Equatable, Identifiable {
    public let start: Date
    public let end: Date?

    public var id: Date {
        start
    }

    public init(start: Date, end: Date?) {
        self.start = start
        self.end = end
    }

    public func duration(now: Date) -> TimeInterval {
        max(0, (end ?? now).timeIntervalSince(start))
    }
}

/// Sleeps and wakes since the Mac booted. Capped, so a Mac that sleeps all day stays small.
public struct SleepHistory: Codable, Sendable, Equatable {
    public static let capacity = 40

    /// The boot this history belongs to: another boot starts it afresh.
    public private(set) var boot: Date
    /// Every sleep since boot, also those whose events were dropped to keep the list short.
    public private(set) var sleepCount: Int
    public private(set) var events: [SleepEvent]

    public init(boot: Date) {
        self.boot = boot
        sleepCount = 0
        events = []
    }

    /// A clock correction moves the boot time by a few seconds, which is still the same boot.
    public static func isSameBoot(_ first: Date, _ second: Date) -> Bool {
        abs(first.timeIntervalSince(second)) < 60
    }

    /// What was saved, if it belongs to this boot. Anything older goes.
    public static func restored(_ saved: SleepHistory?, boot: Date) -> SleepHistory {
        guard var saved, isSameBoot(saved.boot, boot) else { return SleepHistory(boot: boot) }
        saved.events.removeAll { $0.date < boot }
        return saved
    }

    /// A repeated sleep or wake (a dark wake, a missed notification) is not another event.
    public mutating func record(_ kind: SleepEvent.Kind, at date: Date) {
        let last = events.last?.kind ?? .wake
        guard kind != last else { return }
        events.append(SleepEvent(kind: kind, date: date))
        if kind == .sleep {
            sleepCount += 1
        }
        if events.count > Self.capacity {
            events.removeFirst(events.count - Self.capacity)
        }
    }

    public var lastSleep: Date? {
        events.last { $0.kind == .sleep }?.date
    }

    public var lastWake: Date? {
        events.last { $0.kind == .wake }?.date
    }

    /// The awake sessions, newest first. The first one starts at boot while no event has been dropped.
    public func sessions(limit: Int) -> [AwakeSession] {
        var result: [AwakeSession] = []
        var start: Date? = hasLostEvents ? nil : boot
        for event in events {
            switch event.kind {
            case .sleep:
                if let begin = start {
                    result.append(AwakeSession(start: begin, end: event.date))
                }
                start = nil
            case .wake:
                start = event.date
            }
        }
        if let start {
            result.append(AwakeSession(start: start, end: nil))
        }
        return Array(result.reversed().prefix(limit))
    }

    private var hasLostEvents: Bool {
        events.count { $0.kind == .sleep } < sleepCount
    }
}

/// Keeps the history in a small JSON file, so a restart of the app within one boot does not lose it.
@MainActor
@Observable
public final class SleepLog {
    public private(set) var history: SleepHistory
    private let url: URL

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GlassWork/SleepHistory.json")
    }

    public init(url: URL = SleepLog.defaultURL, boot: Date = SystemClock.bootTime() ?? .now) {
        self.url = url
        history = SleepHistory(boot: boot)
    }

    /// Reads the saved file. Nothing is read before this, so tests never touch the real one.
    public func load() {
        let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(SleepHistory.self, from: $0) }
        history = SleepHistory.restored(saved, boot: history.boot)
    }

    public func record(_ kind: SleepEvent.Kind, at date: Date = .now) {
        history.record(kind, at: date)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
