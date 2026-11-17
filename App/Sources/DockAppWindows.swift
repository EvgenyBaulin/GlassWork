import AppKit
import ApplicationServices
import GlassWorkCore

/// The windows of a running app for the Dock's menu: listing them, raising one, and opening a new one.
///
/// Titles come from the window server and need Screen Recording; without it the menu numbers the windows.
/// Raising and "New Window" go through Accessibility and are offered only when it is granted.
enum DockAppWindows {
    /// Per Accessibility read. Set on the app's root element, it holds for every element under it.
    private static let timeout: Float = 0.1
    /// All the reads of one menu bar search together.
    private static let searchBudget = Duration.milliseconds(150)
    /// The app's menu, File and Edit come after the Apple menu, and ⌘N lives in File.
    private static let menuBarItemsSearched = 4

    private static func appElement(pid: Int32) -> AXUIElement {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, timeout)
        return root
    }

    static func list(pid: Int32) -> [DockWindowItem] {
        let info = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
        let raw = (info ?? []).compactMap { entry -> DockWindows.Raw? in
            guard let id = entry[kCGWindowNumber as String] as? Int,
                  let owner = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                      .flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) })
            else { return nil }
            return DockWindows.Raw(
                id: id,
                pid: owner,
                layer: layer,
                bounds: bounds,
                title: entry[kCGWindowName as String] as? String,
                alpha: entry[kCGWindowAlpha as String] as? Double ?? 1
            )
        }
        return DockWindows.items(from: raw, pid: pid)
    }

    /// Brings the window forward. Without Accessibility, or when it cannot be found, only the app comes forward.
    static func raise(_ window: DockWindowItem, of app: NSRunningApplication) {
        app.activate()
        guard AXIsProcessTrusted() else { return }
        let root = appElement(pid: app.processIdentifier)
        let windows = elements(root, "AXWindows")
        let described = windows.map {
            DockWindows.Element(
                title: string($0, "AXTitle"),
                frame: frame(of: $0),
                minimized: (value($0, "AXMinimized") as? Bool) == true
            )
        }
        let siblings = list(pid: app.processIdentifier)
        guard let index = DockWindows.match(window, among: siblings, in: described) else { return }
        if DockWindows.needsRestore(described[index]) {
            AXUIElementSetAttributeValue(windows[index], "AXMinimized" as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(windows[index], "AXRaise" as CFString)
    }

    /// The menu item that ⌘N chooses, if the app has one and it can be used now. Looks at the first few menus only,
    /// and gives up when the time budget is spent, so an app that does not answer cannot hold the caller for long.
    private static func newWindowItem(pid: Int32) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let deadline = ContinuousClock.now + searchBudget
        let root = appElement(pid: pid)
        guard let bar = element(root, "AXMenuBar") else { return nil }
        for barItem in elements(bar, "AXChildren").prefix(menuBarItemsSearched) {
            for menu in elements(barItem, "AXChildren") {
                for item in elements(menu, "AXChildren") {
                    guard ContinuousClock.now < deadline else { return nil }
                    if DockWindows.isCommandN(
                        character: string(item, "AXMenuItemCmdChar"),
                        modifiers: (value(item, "AXMenuItemCmdModifiers") as? NSNumber)?.intValue
                    ), (value(item, "AXEnabled") as? Bool) != false {
                        return item
                    }
                }
            }
            guard ContinuousClock.now < deadline else { return nil }
        }
        return nil
    }

    static func hasNewWindow(pid: Int32) -> Bool {
        newWindowItem(pid: pid) != nil
    }

    /// Brings the app forward and presses the menu item ⌘N would. Pressing it is the same as the keystroke, and it
    /// cannot land in another app if the activation is slow.
    static func newWindow(of app: NSRunningApplication) {
        app.activate()
        guard let item = newWindowItem(pid: app.processIdentifier) else { return }
        AXUIElementPerformAction(item, "AXPress" as CFString)
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let position = axValue(element, "AXPosition") {
            AXValueGetValue(position, .cgPoint, &origin)
        }
        if let extent = axValue(element, "AXSize") {
            AXValueGetValue(extent, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    private static func value(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func element(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let found = value(element, name), CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(found, to: AXUIElement.self)
    }

    private static func axValue(_ element: AXUIElement, _ name: String) -> AXValue? {
        guard let found = value(element, name), CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(found, to: AXValue.self)
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        value(element, name) as? String
    }

    private static func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        (value(element, name) as? [AXUIElement]) ?? []
    }
}
