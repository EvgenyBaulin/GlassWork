import Foundation
import Security

/// Names shared by the app, the helper and the launchd property list.
public enum FanHelperIdentity {
    public static let appIdentifier = "io.github.evgenybaulin.GlassWork"
    public static let helperIdentifier = "io.github.evgenybaulin.GlassWork.FanHelper"
    public static let machService = helperIdentifier
    public static let plistName = "\(helperIdentifier).plist"

    /// Code requirement for a peer signed by the same team, or nil when there is no team to compare.
    /// Without one the caller refuses the connection: an unsigned build must never reach the fans.
    public static func requirement(identifier: String, team: String?) -> String? {
        guard let team, !team.isEmpty, team.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return "identifier \"\(identifier)\" and anchor apple generic "
            + "and certificate leaf[subject.OU] = \"\(team)\""
    }

    /// The team that signed the running process. Read from the signature, so it cannot be faked by a file.
    public static func currentTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

/// The whole XPC surface of the helper: fan commands, and proof that the app is alive.
@objc public protocol FanHelperXPC {
    /// `action` is a `FanCommand.WireAction`; `rpm` matters only for a target.
    func setFan(_ fan: Int, action: Int, rpm: Double, reply: @escaping @Sendable (Bool) -> Void)
    /// Replies true while the helper still holds the fans, false once it has given them back.
    func heartbeat(reply: @escaping @Sendable (Bool) -> Void)
}

public extension FanCommand {
    enum WireAction: Int, Sendable {
        case auto, max, target
    }

    /// Nil for anything that is not a well-formed command.
    init?(fan: Int, wireAction: Int, rpm: Double) {
        switch WireAction(rawValue: wireAction) {
        case .auto: self.init(fan: fan, action: .auto)
        case .max: self.init(fan: fan, action: .max)
        case .target:
            guard rpm.isFinite else { return nil }
            self.init(fan: fan, action: .target(rpm))
        case nil: return nil
        }
    }

    var wire: (action: WireAction, rpm: Double) {
        switch action {
        case .auto: (.auto, 0)
        case .max: (.max, 0)
        case let .target(rpm): (.target, rpm)
        }
    }
}

/// The daemon's XPC server: accepts signed clients, runs commands and watches over them.
public final class FanHelperServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    // @unchecked: `service` and `watchdog` are touched only on `queue`, the rest is immutable.
    private let service: FanHelperService
    private let queue: DispatchQueue
    private let requirement: String?
    private let acceptsUnsigned: Bool
    private let now: @Sendable () -> TimeInterval
    private var watchdog: FanWatchdog
    private var timer: DispatchSourceTimer?
    /// True from the first command that takes a fan until the fans are back with the system.
    private var isArmed = false

    /// With `requirement` nil every connection is refused, unless `acceptsUnsigned` is set for a test.
    public init(
        service: FanHelperService,
        queue: DispatchQueue,
        requirement: String?,
        acceptsUnsigned: Bool = false,
        now: @escaping @Sendable () -> TimeInterval
    ) {
        self.service = service
        self.queue = queue
        self.requirement = requirement
        self.acceptsUnsigned = acceptsUnsigned
        self.now = now
        watchdog = FanWatchdog(now: now())
    }

    /// A crash may have left a fan in manual mode, so every launch starts by taking it back.
    public func start() {
        queue.async { [self] in
            restore()
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 1, repeating: 1)
            source.setEventHandler { [weak self] in self?.checkWatchdog() }
            source.resume()
            timer = source
        }
    }

    /// For the signal handler that ends the daemon. Blocks until the fans are handed back.
    /// Returns false when they could not be.
    public func shutdown() -> Bool {
        queue.sync {
            restore()
            return !isArmed
        }
    }

    public func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let requirement {
            connection.setCodeSigningRequirement(requirement)
        } else if !acceptsUnsigned {
            return false
        }
        connection.exportedInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.exportedObject = Exported(server: self)
        // Both handlers can fire for one connection, and only one of them may count as a departure.
        let departure = Departure { [weak self] in self?.clientLeft() }
        connection.invalidationHandler = { departure.fire() }
        connection.interruptionHandler = { departure.fire() }
        queue.async { [self] in watchdog.clientConnected() }
        connection.resume()
        return true
    }

    fileprivate func handle(_ command: FanCommand?, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            let succeeded = command.map { service.execute($0) } ?? false
            // Stamped after the work: taking control can block for seconds.
            watchdog.contact(at: now())
            // Trusts the command as well as the readback: a watchdog disarmed by mistake is the worse error.
            let tookFan = succeeded && command?.action != .auto
            isArmed = tookFan || !succeeded || service.hasManualFans
            reply(succeeded)
        }
    }

    fileprivate func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            watchdog.contact(at: now())
            reply(isArmed)
        }
    }

    private func clientLeft() {
        queue.async { [self] in
            if watchdog.clientLeft() {
                restore()
            }
        }
    }

    /// Runs on `queue`. A restore that fails leaves the watchdog armed, so it is tried again.
    func checkWatchdog() {
        if isArmed, watchdog.hasExpired(at: now()) {
            restore()
        }
    }

    private func restore() {
        isArmed = !service.restoreAuto()
    }
}

private final class Departure: @unchecked Sendable {
    // @unchecked: `fired` is guarded by `lock`, the action is immutable.
    private let lock = NSLock()
    private var fired = false
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func fire() {
        let isFirst = lock.withLock {
            defer { fired = true }
            return !fired
        }
        if isFirst {
            action()
        }
    }
}

private final class Exported: NSObject, FanHelperXPC, @unchecked Sendable {
    // @unchecked: holds one immutable reference to a server that does its own serialising.
    private let server: FanHelperServer

    init(server: FanHelperServer) {
        self.server = server
    }

    func setFan(_ fan: Int, action: Int, rpm: Double, reply: @escaping @Sendable (Bool) -> Void) {
        server.handle(FanCommand(fan: fan, wireAction: action, rpm: rpm), reply: reply)
    }

    func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
        server.heartbeat(reply: reply)
    }
}
