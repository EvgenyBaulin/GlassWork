import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Shows GlassWork's Dock and hides the system one while it runs.
///
/// Nothing here runs until the owner turns the Dock on in Settings.
@MainActor
final class DockController {
    private unowned let model: AppModel
    private let state = DockLiveState()
    private var window: NSPanel?
    private var screens: NSObjectProtocol?
    private var workspace: [NSObjectProtocol] = []
    private var tracker = DockLaunchTracker()
    private var expiry: Task<Void, Never>?
    private var bundleIDs: [String: String] = [:]
    /// What the view asked for.
    private var requested = DockSpace.rest
    /// What the window is sized for.
    private var space = DockSpace.rest
    private var shrink: Task<Void, Never>?

    /// Long enough for icons to settle before the window closes in around them.
    private static let shrinkDelay = Duration.milliseconds(300)

    init(model: AppModel) {
        self.model = model
    }

    func apply(_ settings: DockSettings) {
        guard settings.isEnabled else {
            close()
            return
        }
        if window == nil {
            SystemDock.hide()
            open()
        }
        state.settings = settings
        refreshRunning()
        place()
    }

    /// Runs on quit, and the saved values also restore after a crash on the next launch.
    func restoreSystemDock() {
        SystemDock.restore()
    }

    private func open() {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .dock
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false
        // Hide Others in any app counts this app too now that it has a Dock icon.
        panel.canHide = false
        let hosting = NSHostingView(rootView: DockView(state: state, monitor: model.monitor, actions: actions))
        // The window's size is decided here. Left to the content it would grow from its corner, sideways.
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel
        screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        observeApps()
    }

    private func observeApps() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        workspace = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
    }

    /// Restores even with no window, so a Dock left hidden by a crash comes back once it is turned off.
    private func close() {
        shrink?.cancel()
        if let screens {
            NotificationCenter.default.removeObserver(screens)
        }
        screens = nil
        workspace.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspace = []
        expiry?.cancel()
        tracker = DockLaunchTracker()
        state.launching = []
        window?.close()
        window = nil
        requested = .rest
        space = .rest
        SystemDock.restore()
    }

    private var actions: DockActions {
        DockActions(
            open: { [weak self] in self?.launch($0) },
            showPanel: { [weak self] in self?.model.showSettings(module: $0) },
            update: { [weak self] change in
                self?.model.store.update { $0.dock.items = change($0.dock.items) }
            },
            needsSpace: { [weak self] space in
                self?.requested = space
                self?.updateSpace()
            },
            commands: { [weak self] in self?.commands(for: $0) ?? [] },
            perform: { [weak self] in self?.perform($0, on: $1) }
        )
    }

    private func runningApp(_ app: DockApp) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first { running in
            let bundleID = bundleIDs[app.path]
            return (bundleID != nil && running.bundleIdentifier == bundleID)
                || running.bundleURL?.path(percentEncoded: false) == app.path
        }
    }

    private func target(of running: NSRunningApplication) -> QuitTarget {
        QuitTarget(
            pid: running.processIdentifier,
            name: running.localizedName ?? "",
            bundleID: running.bundleIdentifier,
            path: running.bundleURL?.path(percentEncoded: false)
        )
    }

    private func commands(for app: DockApp) -> [DockAppCommand] {
        let running = runningApp(app)
        let canQuit = running.map { !QuitPolicy.isProtected(target(of: $0)) } ?? false
        return DockAppCommand.offered(isRunning: running != nil, canQuit: canQuit)
    }

    private func perform(_ command: DockAppCommand, on app: DockApp) {
        let running = runningApp(app)
        switch command {
        case .open: launch(app)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: app.path)])
        case .showAllWindows: running?.activate(options: .activateAllWindows)
        case .hide: running?.hide()
        case .hideOthers: hideOthers(than: running)
        case .quit, .forceQuit:
            if let running {
                model.quit(target(of: running), force: command == .forceQuit)
            }
        }
    }

    private func hideOthers(than kept: NSRunningApplication?) {
        kept?.activate()
        let own = NSRunningApplication.current
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0 != kept && $0 != own
        }
        others.forEach { $0.hide() }
    }

    /// Grows at once, so nothing is cut off. Shrinks late, so nothing is cut off on the way down either.
    private func updateSpace() {
        shrink?.cancel()
        // A bouncing icon rises above the bar, wherever the pointer has gone.
        let wanted = max(requested, state.launching.isEmpty ? .rest : .magnified)
        if wanted >= space {
            space = wanted
            place()
        } else {
            shrink = Task { [weak self] in
                try? await Task.sleep(for: Self.shrinkDelay)
                guard let self, !Task.isCancelled else { return }
                space = wanted
                place()
            }
        }
    }

    /// Bounces from the click until the app is up, and stops at once if it cannot start.
    private func launch(_ app: DockApp) {
        let url = URL(filePath: app.path)
        guard url.pathExtension == "app" else {
            NSWorkspace.shared.open(url)
            return
        }
        tracker.begin(app.path, isRunning: state.running.contains(app.path), at: Date())
        showLaunches()
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            let failed = error != nil
            Task { @MainActor in self?.launchReturned(app.path, failed: failed) }
        }
    }

    private func launchReturned(_ path: String, failed: Bool) {
        if failed {
            tracker.fail(path)
        }
        refreshRunning()
    }

    /// An app that is still starting counts only once it has finished: that is when bouncing stops.
    private func refreshRunning() {
        let apps = state.settings.apps
        for app in apps where bundleIDs[app.path] == nil {
            bundleIDs[app.path] = Bundle(path: app.path)?.bundleIdentifier
        }
        let running = NSWorkspace.shared.runningApplications.filter(\.isFinishedLaunching).map {
            RunningApp(bundleID: $0.bundleIdentifier, path: $0.bundleURL?.path(percentEncoded: false))
        }
        state.running = DockRunningApps.match(apps, bundleIDs: bundleIDs, running: running)
        tracker.update(running: state.running, at: Date())
        showLaunches()
    }

    private func showLaunches() {
        state.launching = tracker.launching
        updateSpace()
        expiry?.cancel()
        guard let deadline = tracker.nextDeadline else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
            guard let self, !Task.isCancelled else { return }
            refreshRunning()
        }
    }

    /// Always the screen with the menu bar: the "main" screen follows the keyboard focus and would make
    /// the Dock hop between displays. Every size shares the same middle and bottom edge, so the bar stays
    /// exactly where it is when the window changes.
    private func place() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let size = DockBarLayout.windowSize(for: space, count: state.settings.items.count, settings: state.settings)
        let frame = CGRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.minY + DockBarLayout.screenGap,
            width: size.width,
            height: size.height
        )
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }
        window.orderFront(nil)
    }
}

/// Saves the system Dock's auto-hide settings, hides it, and puts everything back.
enum SystemDock {
    private static let savedKey = "SystemDockSavedSettings"
    private static let keys = ["autohide", "autohide-delay"]
    private static var dock: CFString {
        "com.apple.dock" as CFString
    }

    static func hide() {
        guard UserDefaults.standard.dictionary(forKey: savedKey) == nil else { return }
        // A key the owner never set stays out of the saved values, so restoring removes it again.
        var saved: [String: Any] = [:]
        for key in keys {
            saved[key] = CFPreferencesCopyAppValue(key as CFString, dock)
        }
        UserDefaults.standard.set(saved, forKey: savedKey)
        write("autohide", true as CFBoolean)
        write("autohide-delay", 1000.0 as CFNumber)
        relaunch()
    }

    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedKey) else { return }
        for key in keys {
            write(key, saved[key] as CFPropertyList?)
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
        relaunch()
    }

    private static func write(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, dock)
        CFPreferencesAppSynchronize(dock)
    }

    /// The Dock reads these settings only at launch.
    ///
    /// Restarted through launchd: a Dock that quits cleanly counts as a successful exit and stays down.
    private static func relaunch() {
        let launchctl = Process()
        launchctl.executableURL = URL(filePath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.Dock.agent"]
        try? launchctl.run()
    }
}
