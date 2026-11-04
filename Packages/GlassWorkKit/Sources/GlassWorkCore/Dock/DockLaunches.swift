import Foundation

/// An app macOS reports as running.
public struct RunningApp: Sendable, Equatable {
    public var bundleID: String?
    public var path: String?

    public init(bundleID: String?, path: String?) {
        self.bundleID = bundleID
        self.path = path
    }
}

/// Finds which Dock apps are running.
public enum DockRunningApps {
    /// Paths alone are not enough: `/Applications/Safari.app` is a link into a system volume, and a running
    /// app reports the far end of it. The bundle identifier is the same on both sides.
    ///
    /// - Parameter bundleIDs: Dock path to bundle identifier, for the apps it could be read from.
    /// - Returns: Dock paths, spelled as they are in the settings.
    public static func match(
        _ apps: [DockApp],
        bundleIDs: [String: String],
        running: [RunningApp]
    ) -> Set<String> {
        let runningIDs = Set(running.compactMap(\.bundleID))
        let runningPaths = Set(running.compactMap(\.path).map(normalized))
        return Set(apps.map(\.path).filter { path in
            if let bundleID = bundleIDs[path], runningIDs.contains(bundleID) {
                return true
            }
            return runningPaths.contains(normalized(path))
        })
    }

    static func normalized(_ path: String) -> String {
        let resolved = URL(filePath: path).resolvingSymlinksInPath().path(percentEncoded: false)
        return resolved.count > 1 && resolved.hasSuffix("/") ? String(resolved.dropLast()) : resolved
    }
}

/// Which Dock apps are on their way up. Bouncing ends when the app runs, fails or runs out of time.
public struct DockLaunchTracker: Equatable, Sendable {
    /// Past this the icon stops bouncing even if nothing was heard. A slow app still gets its dot on launch.
    public static let timeout: TimeInterval = 15

    private var deadlines: [String: Date] = [:]

    public init() {}

    public var launching: Set<String> {
        Set(deadlines.keys)
    }

    public var nextDeadline: Date? {
        deadlines.values.min()
    }

    /// A click on a running app only brings it forward, so there is nothing to wait for.
    public mutating func begin(_ path: String, isRunning: Bool, at date: Date) {
        guard !isRunning else { return }
        deadlines[path] = date.addingTimeInterval(Self.timeout)
    }

    public mutating func fail(_ path: String) {
        deadlines[path] = nil
    }

    public mutating func update(running: Set<String>, at date: Date) {
        deadlines = deadlines.filter { path, deadline in !running.contains(path) && deadline > date }
    }
}
