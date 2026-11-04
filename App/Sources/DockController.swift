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
    private var window: NSPanel?
    private var host: NSHostingView<AnyView>?

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
        render(settings)
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
        window = panel
    }

    private func close() {
        guard window != nil else { return }
        window?.close()
        window = nil
        host = nil
        SystemDock.restore()
    }

    private func render(_ settings: DockSettings) {
        let view = DockView(
            settings: settings,
            running: Set(NSWorkspace.shared.runningApplications
                .compactMap { $0.bundleURL?.path(percentEncoded: false) }),
            monitor: model.monitor,
            actions: DockActions(
                open: { NSWorkspace.shared.open(URL(filePath: $0.path)) },
                showPanel: { [weak self] in self?.model.showSettings(module: $0) },
                update: { [weak self] change in
                    self?.model.store.update { $0.dock.items = change($0.dock.items) }
                }
            )
        )
        let hosting = NSHostingView(rootView: AnyView(view))
        window?.contentView = hosting
        host = hosting
        guard let screen = NSScreen.main else { return }
        let size = hosting.fittingSize
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + 4,
            width: size.width,
            height: size.height
        )
        window?.setFrame(frame, display: true)
        window?.orderFront(nil)
    }
}

/// Saves the system Dock's auto-hide settings, hides it, and puts everything back.
enum SystemDock {
    private static let savedKey = "SystemDockSavedSettings"
    private static var dock: CFString {
        "com.apple.dock" as CFString
    }

    static func hide() {
        guard UserDefaults.standard.dictionary(forKey: savedKey) == nil else { return }
        let saved: [String: Any] = [
            "autohide": CFPreferencesCopyAppValue("autohide" as CFString, dock) ?? false,
            "autohide-delay": CFPreferencesCopyAppValue("autohide-delay" as CFString, dock) ?? 0.0,
        ]
        UserDefaults.standard.set(saved, forKey: savedKey)
        write("autohide", true as CFBoolean)
        write("autohide-delay", 1000.0 as CFNumber)
        relaunch()
    }

    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedKey) else { return }
        write("autohide", saved["autohide"] as CFPropertyList?)
        write("autohide-delay", saved["autohide-delay"] as CFPropertyList?)
        UserDefaults.standard.removeObject(forKey: savedKey)
        relaunch()
    }

    private static func write(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, dock)
        CFPreferencesAppSynchronize(dock)
    }

    private static func relaunch() {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").forEach { $0.terminate() }
    }
}
