import Foundation

/// The app's XPC connection to the helper.
public final class FanHelperConnection: FanHelperClient, @unchecked Sendable {
    // @unchecked: `connection` is immutable and NSXPCConnection is safe to call from any thread.
    private let connection: NSXPCConnection

    /// `onLost` fires when the helper goes away, for any reason.
    public init(connection: NSXPCConnection, onLost: @escaping @Sendable () -> Void) {
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperXPC.self)
        connection.invalidationHandler = onLost
        connection.interruptionHandler = onLost
        connection.resume()
    }

    /// Connects to the installed daemon, or returns nil for a build no helper would trust.
    public static func privileged(onLost: @escaping @Sendable () -> Void) -> FanHelperConnection? {
        let requirement = FanHelperIdentity.requirement(
            identifier: FanHelperIdentity.helperIdentifier,
            team: FanHelperIdentity.currentTeam()
        )
        guard let requirement else { return nil }
        let connection = NSXPCConnection(machServiceName: FanHelperIdentity.machService, options: .privileged)
        // Checked both ways: nothing else may pose as the helper under its service name.
        connection.setCodeSigningRequirement(requirement)
        return FanHelperConnection(connection: connection, onLost: onLost)
    }

    public func send(_ command: FanCommand) async -> Bool {
        await call { proxy, reply in
            let wire = command.wire
            proxy.setFan(command.fan, action: wire.action.rawValue, rpm: wire.rpm, reply: reply)
        }
    }

    public func heartbeat() async -> Bool {
        await call { proxy, reply in proxy.heartbeat(reply: reply) }
    }

    public func disconnect() {
        connection.invalidate()
    }

    private func call(_ body: (FanHelperXPC, @escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            // XPC calls either the reply or the error handler, but nothing promises it is only one.
            let once = Once { continuation.resume(returning: $0) }
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in once.finish(false) }
            guard let helper = proxy as? FanHelperXPC else {
                once.finish(false)
                return
            }
            body(helper) { once.finish($0) }
        }
    }
}

private final class Once: @unchecked Sendable {
    // @unchecked: `finished` is guarded by `lock`, the handler is immutable.
    private let lock = NSLock()
    private var finished = false
    private let handler: @Sendable (Bool) -> Void

    init(handler: @escaping @Sendable (Bool) -> Void) {
        self.handler = handler
    }

    func finish(_ value: Bool) {
        let isFirst = lock.withLock {
            defer { finished = true }
            return !finished
        }
        if isFirst {
            handler(value)
        }
    }
}
