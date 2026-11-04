import Foundation

/// What a Quit button points at: an app, or a process from a raw list, which has no bundle id.
public struct QuitTarget: Sendable, Equatable {
    public var pid: Int32
    public var name: String
    public var bundleID: String?
    public var path: String?

    public init(pid: Int32, name: String, bundleID: String? = nil, path: String? = nil) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.path = path
    }
}

public extension AppUsage {
    var target: QuitTarget {
        QuitTarget(pid: pid, name: name, bundleID: bundleID, path: path)
    }

    /// True when no list offers to quit this app.
    var isProtected: Bool {
        QuitPolicy.isProtected(target)
    }
}

public extension ProcessUsage {
    var target: QuitTarget {
        QuitTarget(pid: pid, name: name)
    }
}

/// What must keep running. The lists hide their buttons for these, and the quit path refuses them anyway.
public enum QuitPolicy {
    /// This app, so nobody quits the Dock bar and the fans' failsafe from a list, and its identity for tests.
    public struct Identity: Sendable {
        public var pid: Int32
        public var bundleID: String?

        public init(pid: Int32, bundleID: String?) {
            self.pid = pid
            self.bundleID = bundleID
        }

        public static var current: Identity {
            Identity(pid: ProcessInfo.processInfo.processIdentifier, bundleID: Bundle.main.bundleIdentifier)
        }
    }

    /// Names alone are all a line of `ps` gives, so these are the processes a Mac cannot do without.
    private static let names: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow", "logind", "Dock", "Finder", "SystemUIServer",
        "ControlCenter", "NotificationCenter", "Spotlight", "coreaudiod", "coreservicesd", "cfprefsd", "distnoted",
        "fseventsd", "mds", "mds_stores", "notifyd", "opendirectoryd", "powerd", "securityd", "syslogd", "tccd",
        "trustd", "UserEventAgent", "usbd",
    ]
    /// Everything macOS runs for itself. `/System/Applications`, with Music and Notes, is not among them.
    private static let folders = ["/System/Library/", "/usr/libexec/", "/usr/sbin/", "/sbin/"]
    private static let ownPrefix = "GlassWork"

    /// Protected ones are not offered Quit either: a quit Dock stays down and a quit `loginwindow` logs out.
    public static func isProtected(_ target: QuitTarget, own: Identity = .current) -> Bool {
        if target.pid <= 1 || target.pid == own.pid {
            return true
        }
        if let id = own.bundleID, let bundleID = target.bundleID, bundleID == id || bundleID.hasPrefix(id + ".") {
            return true
        }
        if names.contains(target.name) || target.name.hasPrefix(ownPrefix) {
            return true
        }
        return target.path.map { path in folders.contains { path.hasPrefix($0) } } ?? false
    }
}

public enum QuitOutcome: Sendable, Equatable {
    /// The app was asked or the process was signalled. An app may still say no, or ask about unsaved work.
    case sent
    case refused
    /// Something else has that pid now, or nothing does.
    case gone
    case failed
}

/// The system's side of quitting. Tests substitute their own, so they never touch a real process.
public protocol QuitSystem {
    /// Who holds this pid right now. The name is the executable's.
    func identity(of pid: Int32) -> QuitTarget?
    func stop(_ pid: Int32, force: Bool) -> Bool
}

/// The one way anything in GlassWork quits an app or process.
public struct QuitService {
    private let system: any QuitSystem
    private let own: QuitPolicy.Identity

    public init(system: any QuitSystem, own: QuitPolicy.Identity = .current) {
        self.system = system
        self.own = own
    }

    /// Lists can be seconds old, so what holds the pid now is checked, and judged, before anything is sent.
    public func quit(_ target: QuitTarget, force: Bool) -> QuitOutcome {
        guard !QuitPolicy.isProtected(target, own: own) else { return .refused }
        guard let current = system.identity(of: target.pid), Self.isSame(target, current) else { return .gone }
        guard !QuitPolicy.isProtected(current, own: own) else { return .refused }
        return system.stop(target.pid, force: force) ? .sent : .failed
    }

    /// `ps` cuts long names, so one may be the start of the other.
    private static func isSame(_ target: QuitTarget, _ current: QuitTarget) -> Bool {
        if let id = target.bundleID {
            return id == current.bundleID
        }
        return target.name.hasPrefix(current.name) || current.name.hasPrefix(target.name)
    }
}
