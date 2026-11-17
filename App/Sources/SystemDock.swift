import Foundation

/// Saves the system Dock's auto-hide settings, hides it, and puts everything back.
enum SystemDock {
    private static let savedKey = "SystemDockSavedSettings"
    private static let keys = ["autohide", "autohide-delay"]
    private static var dock: CFString {
        "com.apple.dock" as CFString
    }

    /// What was saved when GlassWork Dock took over. A value the owner never set is nil.
    struct Saved: Equatable {
        var autoHides: Bool?
        var autoHideDelay: Double?
    }

    /// Nil while the system Dock is untouched. Only reads GlassWork's own copy, never the system's settings.
    static var saved: Saved? {
        guard let values = UserDefaults.standard.dictionary(forKey: savedKey) else { return nil }
        return Saved(autoHides: values["autohide"] as? Bool, autoHideDelay: values["autohide-delay"] as? Double)
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
