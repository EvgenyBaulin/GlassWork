import Foundation

/// What can be told about backups without Full Disk Access or mounting the backup disk.
public struct TimeMachineStatus: Codable, Sendable, Equatable {
    public enum State: Codable, Sendable, Equatable {
        /// No backup disk has been chosen.
        case notConfigured
        case idle
        /// `progress` is nil while macOS is still preparing.
        case running(progress: Double?, secondsLeft: Double?)
        /// There is a disk, but the record of backups cannot be read without Full Disk Access.
        case needsPermission
    }

    public var state: State
    public var destination: String?
    public var isAutomatic: Bool
    public var lastBackup: Date?
    /// Finished backups, oldest first. Empty unless macOS lists them in its preferences.
    public var backups: [Date]

    public init(
        state: State,
        destination: String? = nil,
        isAutomatic: Bool = false,
        lastBackup: Date? = nil,
        backups: [Date] = []
    ) {
        self.state = state
        self.destination = destination
        self.isAutomatic = isAutomatic
        self.lastBackup = lastBackup
        self.backups = backups
    }

    /// Backups normally run at least weekly, so an older date means something stopped working.
    public static let overdueAfter: TimeInterval = 7 * 86400

    public func isOverdue(at date: Date) -> Bool {
        lastBackup.map { date.timeIntervalSince($0) > Self.overdueAfter } ?? false
    }

    /// False when the date is only the last activity macOS noted, which may not be a finished backup.
    public var isConfirmed: Bool {
        !backups.isEmpty
    }

    /// Whether a backup finished on each of the last `count` days, oldest first, ending today.
    public func days(_ count: Int, at date: Date, calendar: Calendar = .current) -> [(date: Date, backedUp: Bool)] {
        let today = calendar.startOfDay(for: date)
        let done = Set((backups + [lastBackup].compactMap(\.self)).map { calendar.startOfDay(for: $0) })
        return (0 ..< count).reversed().compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: today).map { ($0, done.contains($0)) }
        }
    }
}

/// What the system preferences file tells.
public struct TimeMachinePreferences: Sendable, Equatable {
    public var isAutomatic: Bool
    public var last: Date?
    public var backups: [Date]

    public init(isAutomatic: Bool, last: Date?, backups: [Date]) {
        self.isAutomatic = isAutomatic
        self.last = last
        self.backups = backups
    }
}

public enum TimeMachineParser {
    /// Parses `tmutil status -X`.
    public static func progress(_ plist: Data) -> TimeMachineStatus.State? {
        guard let root = dictionary(plist) else { return nil }
        guard number(root["Running"]) == 1 else { return .idle }
        let details = root["Progress"] as? [String: Any]
        let share = number(details?["Percent"]) ?? number(root["Percent"])
        return .running(
            progress: share.flatMap { $0 >= 0 ? min($0, 1) : nil },
            secondsLeft: number(details?["TimeRemaining"]).flatMap { $0 >= 0 ? $0 : nil }
        )
    }

    /// Parses `tmutil destinationinfo -X`: the name of the first backup disk.
    public static func destination(_ plist: Data) -> String? {
        let destinations = dictionary(plist)?["Destinations"] as? [[String: Any]]
        return destinations?.first?["Name"] as? String
    }

    /// Reads the system preferences file, which holds no list of backups on recent macOS.
    public static func preferences(_ plist: Data) -> TimeMachinePreferences? {
        guard let root = dictionary(plist) else { return nil }
        let destinations = root["Destinations"] as? [[String: Any]] ?? []
        let dates = destinations.flatMap { $0["SnapshotDates"] as? [Date] ?? [] }.sorted()
        let activity = (root["LastBackupActivity"] as? String).flatMap(activityDate)
        return TimeMachinePreferences(
            isAutomatic: number(root["AutoBackup"]) == 1,
            last: dates.last ?? activity,
            backups: dates
        )
    }

    /// One status out of the three sources. `preferences` is nil when macOS refused to open the file.
    public static func status(
        running: TimeMachineStatus.State?,
        destination: String?,
        preferences: TimeMachinePreferences?
    ) -> TimeMachineStatus {
        guard let destination else { return TimeMachineStatus(state: .notConfigured) }
        let state: TimeMachineStatus.State = if case .running = running {
            running ?? .idle
        } else {
            preferences == nil ? .needsPermission : .idle
        }
        return TimeMachineStatus(
            state: state,
            destination: destination,
            isAutomatic: preferences?.isAutomatic ?? false,
            lastBackup: preferences?.last,
            backups: preferences?.backups ?? []
        )
    }

    /// Reads `2024-11-04-152715`, which macOS writes in local time.
    private static func activityDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.date(from: text)
    }

    private static func dictionary(_ plist: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: plist, format: nil)) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

public enum TimeMachineReader {
    private static let tool = "/usr/bin/tmutil"
    private static let preferences = URL(filePath: "/Library/Preferences/com.apple.TimeMachine.plist")

    /// Only asks. `latestbackup` and `listbackups` are avoided on purpose: they try to mount the backup disk.
    public static func read(using runner: ProcessRunning = ProcessRunner()) async -> TimeMachineStatus {
        let status = try? await runner.run(tool, arguments: ["status", "-X"], timeout: 5)
        let destinations = try? await runner.run(tool, arguments: ["destinationinfo", "-X"], timeout: 5)
        return TimeMachineParser.status(
            running: status.flatMap { TimeMachineParser.progress(Data($0.stdout.utf8)) },
            destination: destinations.flatMap { TimeMachineParser.destination(Data($0.stdout.utf8)) },
            preferences: (try? Data(contentsOf: preferences)).flatMap(TimeMachineParser.preferences)
        )
    }
}
