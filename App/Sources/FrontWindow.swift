import AppKit
import ApplicationServices
import GlassWorkCore

/// The focused window of the app in front, reached through Accessibility.
///
/// Frames going in and out use the system's coordinates: only this type knows Accessibility counts from the
/// top. Reading needs access to be granted already; nothing here can raise the macOS dialog.
@MainActor
struct FrontWindow {
    /// Calls run on the main thread, so a hung app must not hold the menu bar up for the default six seconds.
    private static let timeout: Float = 0.5

    let app: pid_t
    private let element: AXUIElement
    private let primaryHeight: Double

    /// Nil when the front app has no window to offer, as Finder with only the desktop.
    static func current(primaryHeight: Double) -> FrontWindow? {
        guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(front.processIdentifier)
        AXUIElementSetMessagingTimeout(application, timeout)
        let attributes = [kAXFocusedWindowAttribute, kAXMainWindowAttribute]
        guard let element = attributes.lazy.compactMap({ Self.window(attribute: $0, of: application) }).first else {
            return nil
        }
        AXUIElementSetMessagingTimeout(element, timeout)
        return FrontWindow(app: front.processIdentifier, element: element, primaryHeight: primaryHeight)
    }

    private static func window(attribute: String, of application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    /// A window in its own full screen Space has no frame of its own to change.
    var isFullScreen: Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else {
            return false
        }
        return value as? Bool ?? false
    }

    var canMove: Bool {
        isSettable(kAXPositionAttribute)
    }

    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = value(of: kAXPositionAttribute), AXValueGetValue(position, .cgPoint, &origin),
              let extent = value(of: kAXSizeAttribute), AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return ScreenSpace.flipped(CGRect(origin: origin, size: size), primaryHeight: primaryHeight)
    }

    /// Moves the window and returns where it really went: apps can refuse or round a size.
    ///
    /// The size goes first and again last. The first keeps a large window from being pushed back by the edge
    /// of the display it is leaving, the second is for a window its old display would not let grow.
    func place(_ target: CGRect, in visible: CGRect) -> CGRect? {
        let resizes = isSettable(kAXSizeAttribute)
        if resizes {
            resize(to: target.size)
        }
        moveOrigin(of: target)
        if resizes {
            resize(to: target.size)
        }
        guard let landed = frame else { return nil }
        let settled = TilePlanner.settled(landed, in: visible)
        guard settled != landed else { return landed }
        moveOrigin(of: settled)
        return frame
    }

    private func moveOrigin(of target: CGRect) {
        var origin = ScreenSpace.flipped(target, primaryHeight: primaryHeight).origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func resize(to target: CGSize) {
        var size = target
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private func value(of attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }
}
