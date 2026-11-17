import AppKit
import ApplicationServices
import GlassWorkCore

/// Reads the badges the system Dock shows, through Accessibility. The system Dock keeps running (hidden) while
/// GlassWork's Dock is up, and each of its items says what its badge reads in `AXStatusLabel`.
enum DockBadgeReader {
    private static let dockID = "com.apple.dock"
    /// Shorter than the default, so a Dock that is restarting cannot hold the poll.
    private static let timeout: Float = 0.5

    /// Empty without Accessibility, or while the system Dock is not running. Safe off the main thread.
    static func read() -> [DockBadges.Item] {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: dockID).first?.processIdentifier
        else { return [] }
        let root = AXUIElementCreateApplication(pid)
        var items: [DockBadges.Item] = []
        for list in elements(root, "AXChildren") where string(list, "AXRole") == "AXList" {
            for item in elements(list, "AXChildren") {
                items.append(DockBadges.Item(
                    url: (value(item, "AXURL") as? URL)?.absoluteString,
                    label: string(item, "AXStatusLabel")
                ))
            }
        }
        return items
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        (value(element, name) as? [AXUIElement]) ?? []
    }
}
