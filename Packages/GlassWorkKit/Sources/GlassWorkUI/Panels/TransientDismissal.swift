import AppKit

/// Closes a short-lived panel on everything that means the user has moved on.
///
/// A global mouse monitor alone is not enough: it sees only clicks that reach other apps. Clicks on the
/// app's own windows, Esc, ⌘Tab and a Space change never reach it, and the panel joins every Space.
@MainActor
public final class TransientDismissal {
    private let panel: NSWindow
    private let isStatusItem: (NSWindow) -> Bool
    private let dismiss: () -> Void
    private let ownProcess: pid_t
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private static let escapeKey: UInt16 = 53

    /// - Parameter isStatusItem: Tells the app's own status item windows from the rest.
    public init(
        panel: NSWindow,
        isStatusItem: @escaping (NSWindow) -> Bool = { _ in false },
        ownProcess: pid_t = ProcessInfo.processInfo.processIdentifier,
        dismiss: @escaping () -> Void
    ) {
        self.panel = panel
        self.isStatusItem = isStatusItem
        self.ownProcess = ownProcess
        self.dismiss = dismiss
    }

    public func start() {
        monitorMouse()
        monitorEscape()
        observeWorkspace()
    }

    public func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
    }

    /// A left click on a status item is left alone: closing on the press would make the same item's
    /// action, which runs on release, open the panel again.
    func shouldDismiss(clickIn window: NSWindow?, type: NSEvent.EventType) -> Bool {
        guard let window, window !== panel, window.sheetParent !== panel else { return false }
        // The Git panel's folder chooser belongs to the panel that opened it.
        guard !(window is NSSavePanel) else { return false }
        return !(type == .leftMouseDown && isStatusItem(window))
    }

    func shouldDismiss(keyCode: UInt16, in window: NSWindow?) -> Bool {
        keyCode == Self.escapeKey && window === panel
    }

    func shouldDismiss(activated process: pid_t?) -> Bool {
        process != ownProcess
    }

    private func monitorMouse() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(outside)
        }
        if let inside = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.shouldDismiss(clickIn: event.window, type: event.type) else { return }
                self.dismiss()
            }
            return event
        }) {
            monitors.append(inside)
        }
    }

    private func monitorEscape() {
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let isHandled = MainActor.assumeIsolated {
                guard let self, self.shouldDismiss(keyCode: event.keyCode, in: event.window) else { return false }
                self.dismiss()
                return true
            }
            return isHandled ? nil : event
        }) {
            monitors.append(escape)
        }
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let process = app?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.shouldDismiss(activated: process) else { return }
                self.dismiss()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        })
    }
}
