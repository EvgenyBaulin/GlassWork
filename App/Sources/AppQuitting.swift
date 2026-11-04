import AppKit
import GlassWorkCore

/// Quits through the workspace, which gives an app the chance to save. A process with no app gets a signal.
struct WorkspaceQuitSystem: QuitSystem {
    func identity(of pid: Int32) -> QuitTarget? {
        let app = NSRunningApplication(processIdentifier: pid)
        let path = KernelProcessTable.path(of: pid)
        guard let name = path.map({ URL(filePath: $0).lastPathComponent }) ?? app?.localizedName else { return nil }
        return QuitTarget(
            pid: pid,
            name: name,
            bundleID: app?.bundleIdentifier,
            path: app?.bundleURL?.path(percentEncoded: false) ?? path
        )
    }

    func stop(_ pid: Int32, force: Bool) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid) {
            return force ? app.forceTerminate() : app.terminate()
        }
        return kill(pid, force ? SIGKILL : SIGTERM) == 0
    }
}

/// Keeps the list of running apps in the store. Launches and quits are rare, reads are not, so the workspace is
/// asked only when something changes.
@MainActor
final class RunningAppsObserver {
    private let store: AppUsageStore
    private var observers: [NSObjectProtocol] = []

    init(store: AppUsageStore) {
        self.store = store
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        update()
    }

    private func update() {
        store.running = NSWorkspace.shared.runningApplications.map(Self.info).filter(\.isListed)
    }

    private static func info(_ app: NSRunningApplication) -> RunningAppInfo {
        let role: RunningAppInfo.Role = switch app.activationPolicy {
        case .regular: .regular
        case .accessory: .accessory
        default: .background
        }
        return RunningAppInfo(
            pid: app.processIdentifier,
            name: app.localizedName ?? app.bundleIdentifier ?? "",
            bundleID: app.bundleIdentifier,
            path: app.bundleURL?.path(percentEncoded: false),
            role: role
        )
    }
}
