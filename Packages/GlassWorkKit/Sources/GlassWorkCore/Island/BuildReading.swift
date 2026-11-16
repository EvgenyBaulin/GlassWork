import Foundation

/// A build that is running now. The name is nil when the tool does not say which scheme it builds.
public struct BuildRun: Sendable, Equatable {
    public var name: String?
    public var started: Date

    public init(name: String?, started: Date) {
        self.name = name
        self.started = started
    }
}

/// A build that has just ended, as Xcode's log store recorded it.
public struct BuildResult: Sendable, Equatable {
    public var name: String
    public var succeeded: Bool
    public var errors: Int
    public var warnings: Int
    public var started: Date
    public var finished: Date

    public init(name: String, succeeded: Bool, errors: Int, warnings: Int, started: Date, finished: Date) {
        self.name = name
        self.succeeded = succeeded
        self.errors = errors
        self.warnings = warnings
        self.started = started
        self.finished = finished
    }

    public var duration: TimeInterval {
        max(finished.timeIntervalSince(started), 0)
    }
}

public enum BuildReading: Sendable, Equatable {
    case running(BuildRun)
    case finished(BuildResult)
}

/// One build in a `LogStoreManifest.plist`.
public struct BuildLogEntry: Sendable, Equatable {
    public var id: String
    public var title: String
    public var scheme: String?
    /// The manifest's one-letter status: "S" succeeded, "W" with warnings, "E" failed, others stopped early.
    public var status: String
    public var errors: Int
    public var warnings: Int
    public var started: Date
    public var stopped: Date?

    /// The scheme, or the title without its leading verb.
    public var name: String {
        if let scheme, !scheme.isEmpty {
            return scheme
        }
        for prefix in ["Build ", "Building "] where title.hasPrefix(prefix) {
            return String(title.dropFirst(prefix.count))
        }
        return title
    }

    /// Cancelled and unfinished builds have neither outcome.
    public var result: BuildResult? {
        guard let stopped else { return nil }
        let failed = status == "E" || errors > 0
        guard failed || status == "S" || status == "W" else { return nil }
        return BuildResult(
            name: name, succeeded: !failed, errors: errors, warnings: warnings, started: started, finished: stopped
        )
    }
}

public enum BuildManifest {
    /// Parses Xcode's `Logs/Build/LogStoreManifest.plist`. Unreadable files and malformed entries give nothing.
    public static func parse(_ data: Data) -> [BuildLogEntry] {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let logs = root["logs"] as? [String: [String: Any]]
        else { return [] }
        return logs.compactMap { key, log in
            guard let title = log["title"] as? String,
                  let started = (log["timeStartedRecording"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
            else { return nil }
            let observable = log["primaryObservable"] as? [String: Any] ?? [:]
            return BuildLogEntry(
                id: log["uniqueIdentifier"] as? String ?? key,
                title: title,
                scheme: log["schemeIdentifier-schemeName"] as? String,
                status: observable["highLevelStatus"] as? String ?? "",
                errors: observable["totalNumberOfErrors"] as? Int ?? 0,
                warnings: observable["totalNumberOfWarnings"] as? Int ?? 0,
                started: started,
                stopped: (log["timeStoppedRecording"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
            )
        }
    }

    /// The newest finished build that ended after the run began, so an older build in the same store is never
    /// reported.
    public static func result(for run: BuildRun, in entries: [BuildLogEntry]) -> BuildResult? {
        entries
            .filter { entry in
                guard let stopped = entry.stopped else { return false }
                // The run is noticed up to one poll after it begins.
                return stopped >= run.started.addingTimeInterval(-2)
            }
            .max { ($0.stopped ?? .distantPast) < ($1.stopped ?? .distantPast) }?
            .result
    }
}

public enum BuildProcesses {
    /// Tools whose presence means a build is running.
    static let builders: Set<String> = ["xcodebuild", "swift-build"]
    /// Xcode's build service (named XCB, later SWB) stays alive while Xcode is idle, so it counts only beside a
    /// compiler or linker.
    static let services: Set<String> = ["XCBBuildService", "SWBBuildService"]
    static let workers: Set<String> = ["swift-frontend", "swiftc", "clang", "ld"]

    public static func isBuilding(_ processes: [ProcessUsage]) -> Bool {
        let names = Set(processes.map(\.name))
        return !names
            .isDisjoint(with: builders) || (!names.isDisjoint(with: services) && !names.isDisjoint(with: workers))
    }

    public static func builderPID(_ processes: [ProcessUsage]) -> Int32? {
        processes.first { $0.name == "xcodebuild" }?.pid
    }

    /// The scheme or target from an `xcodebuild` command line, as `ps -o args=` prints it.
    public static func scheme(fromArguments line: String) -> String? {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for flag in ["-scheme", "-target"] {
            if let index = words.firstIndex(of: flag), words.indices.contains(index + 1) {
                return words[index + 1]
            }
        }
        return nil
    }
}
