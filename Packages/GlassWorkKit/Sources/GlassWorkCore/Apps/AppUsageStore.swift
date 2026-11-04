import Foundation
import Observation

/// What every app uses now, and over the last week.
///
/// Reads ride on the monitor's tick, so they add no wake-ups of their own and stop with it when the Mac sleeps.
@MainActor
@Observable
public final class AppUsageStore {
    public private(set) var apps: [AppUsage] = []
    public private(set) var history = AppUsageHistory()

    /// The apps to report on. The list changes only when an app starts or quits, so the app keeps it here instead
    /// of asking the workspace on every read.
    @ObservationIgnored public var running: [RunningAppInfo] = [] {
        didSet {
            guard running != oldValue else { return }
            // Quitting shows at once. A new app waits for the next read.
            let pids = Set(running.map(\.pid))
            apps.removeAll { !pids.contains($0.pid) }
            refresh()
        }
    }

    /// Enough for a week of history: one read costs about 3 ms, so this is 0.005% of one core.
    public nonisolated static let backgroundInterval: TimeInterval = 60
    /// While a list is on screen. Faster would make the figures hard to read.
    public nonisolated static let liveInterval: TimeInterval = 5
    /// Two reads closer than this would measure noise.
    private static let shortestInterval: TimeInterval = 1
    /// A tick lands a little early or late, and missing by a hair would cost a whole tick.
    private static let tolerance: TimeInterval = 0.5
    private static let compactionInterval: TimeInterval = 86400

    @ObservationIgnored private let reader: AppUsageReader
    @ObservationIgnored private let log: AppUsageLog
    @ObservationIgnored private var isReading = false
    @ObservationIgnored private var lastRead = Date.distantPast
    @ObservationIgnored private var lastCompaction = Date()
    /// CPU needs two reads, so the first is followed up soon.
    @ObservationIgnored private var hasCPU = false

    public init(reader: AppUsageReader = AppUsageReader(), log: AppUsageLog = AppUsageLog()) {
        self.reader = reader
        self.log = log
    }

    /// Reads the file. Separate from `init`, so a monitor made in a test leaves the user's files alone.
    public func load(at date: Date = Date()) async {
        let log = log
        let records = await Task.detached(priority: .utility) { log.load(now: date) }.value
        history.restore(records, now: date)
    }

    public func tick(at date: Date, isLive: Bool) {
        let pace = isLive || !hasCPU ? Self.liveInterval : Self.backgroundInterval
        guard date.timeIntervalSince(lastRead) >= pace - Self.tolerance else { return }
        read(at: date)
    }

    /// Reads now, for a list that just opened.
    public func refresh(at date: Date = Date()) {
        guard date.timeIntervalSince(lastRead) >= Self.shortestInterval else { return }
        read(at: date)
    }

    private func read(at date: Date) {
        guard !isReading, !running.isEmpty else { return }
        isReading = true
        lastRead = date
        let running = running
        Task {
            let reading = await reader.read(running, at: date)
            isReading = false
            apply(reading, at: date)
        }
    }

    private func apply(_ reading: AppUsageReading, at date: Date) {
        hasCPU = reading.hasCPU
        // An app that quit during the read stays gone.
        let pids = Set(running.map(\.pid))
        apps = reading.apps.filter { pids.contains($0.pid) }
        guard reading.hasCPU, let record = history.record(reading.apps, at: date) else { return }
        save(record, at: date)
    }

    private func save(_ record: AppUsageRecord, at date: Date) {
        let log = log
        let compacts = date.timeIntervalSince(lastCompaction) >= Self.compactionInterval
        if compacts {
            lastCompaction = date
        }
        Task.detached(priority: .utility) {
            try? log.append(record)
            if compacts {
                _ = log.load(now: date)
            }
        }
    }

    /// Writes what the file does not have yet, right before the app quits.
    public func saveNow() {
        if let record = history.pending() {
            try? log.append(record)
        }
    }

    /// Fills the store by hand, for tests and previews.
    public func show(_ apps: [AppUsage], history: AppUsageHistory = AppUsageHistory()) {
        self.apps = apps
        self.history = history
    }

    /// Oldest first, thinned to what a chart can use.
    public func points(for id: AppUsage.ID, since date: Date, limit: Int) -> [AppUsagePoint] {
        AppUsageHistory.thinned(history.points(for: id, since: date), limit: limit)
    }
}
