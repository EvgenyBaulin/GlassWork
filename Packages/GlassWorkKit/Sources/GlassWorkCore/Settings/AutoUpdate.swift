import Foundation

/// What the background rebuild (`scripts/auto-update.sh`) has left on disk. The app only reads it.
public struct AutoUpdateStatus: Sendable, Equatable {
    public var isInstalled: Bool
    public var lastBuild: Date?
    /// The next time the LaunchAgent wakes up.
    public var nextCheck: Date
    /// The first check that will rebuild. Nil while the agent is off.
    public var nextBuild: Date?

    public init(isInstalled: Bool, lastBuild: Date?, nextCheck: Date, nextBuild: Date?) {
        self.isInstalled = isInstalled
        self.lastBuild = lastBuild
        self.nextCheck = nextCheck
        self.nextBuild = nextBuild
    }
}

public enum AutoUpdate {
    /// The same values as in `scripts/auto-update.sh`.
    public static let label = "io.github.evgenybaulin.glasswork.autoupdate"
    public static let checkHour = 12
    public static let intervalDays = 5

    public static func agentURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/LaunchAgents/\(label).plist")
    }

    public static func stateFolder(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/GlassWork/AutoUpdate")
    }

    /// Touched after every finished rebuild.
    public static func stampURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        stateFolder(home: home).appending(path: "last-build")
    }

    public static func logURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        stateFolder(home: home).appending(path: "auto-update.log")
    }

    /// The first 12:00 after `date`.
    public static func nextCheck(after date: Date, calendar: Calendar = .current) -> Date {
        let components = DateComponents(hour: checkHour, minute: 0, second: 0)
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date
    }

    /// The first check at least `intervalDays` after the last build, as the script decides it.
    /// Without a build on record the next check rebuilds.
    public static func nextBuild(lastBuild: Date?, now: Date, calendar: Calendar = .current) -> Date {
        guard let lastBuild else { return nextCheck(after: now, calendar: calendar) }
        let due = lastBuild.addingTimeInterval(TimeInterval(intervalDays * 86400))
        // A check exactly at the due moment still rebuilds, so look from just before it.
        let start = max(now, due.addingTimeInterval(-1))
        return nextCheck(after: start, calendar: calendar)
    }

    public static func status(
        isInstalled: Bool,
        lastBuild: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AutoUpdateStatus {
        AutoUpdateStatus(
            isInstalled: isInstalled,
            lastBuild: lastBuild,
            nextCheck: nextCheck(after: now, calendar: calendar),
            nextBuild: isInstalled ? nextBuild(lastBuild: lastBuild, now: now, calendar: calendar) : nil
        )
    }
}
