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
    }

    /// Restores even with no window, so a Dock left hidden by a crash comes back once it is turned off.
    private func close() {
        shrink?.cancel()
        if let screens {
            NotificationCenter.default.removeObserver(screens)
        }
        screens = nil
        window?.close()
        window = nil
        requested = .rest
        space = .rest
        SystemDock.restore()
    }

    private var actions: DockActions {
        DockActions(
            open: { NSWorkspace.shared.open(URL(filePath: $0.path)) },
            showPanel: { [weak self] in self?.model.showSettings(module: $0) },
            update: { [weak self] change in
                self?.model.store.update { $0.dock.items = change($0.dock.items) }
            },
            needsSpace: { [weak self] space in
                self?.requested = space
                self?.updateSpace()
            }
        )
    }

    /// Grows at once, so nothing is cut off. Shrinks late, so nothing is cut off on the way down either.
    private func updateSpace() {
        shrink?.cancel()
        let wanted = requested
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

    private func refreshRunning() {
        state.running = Set(NSWorkspace.shared.runningApplications
            .compactMap { $0.bundleURL?.path(percentEncoded: false) })
    }

    /// Always the screen with the menu bar: the "main" screen follows the keyboard focus and would make
    /// the Dock hop between displays. Every size shares the same middle and bottom edge, so the bar stays
    /// exactly where it is when the window changes.
    private func place() {
        guard let window, let screen = NSScreen.screens.first else { return }
        let size = DockBarLayout.windowSize(for: space, count: state.settings.items.count, settings: state.settings)
        let frame = CGRect(
            x: (screen.frame.midX - size.width / 2).rounded(),
            y: screen.frame.minY + 4,
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
