import AppKit
import ApplicationServices
import GlassWorkCore

/// Reads other apps' menu bar items through Accessibility, and presses one.
///
/// Every call blocks on other processes, so callers run it off the main thread. A short messaging timeout keeps
/// one hung app from stalling the rest.
enum MenuBarInventory {
    struct App: Sendable {
        var pid: Int32
        var name: String
    }

    private static let timeout: Float = 0.1

    /// The apps worth asking: everything but this app and the ones that can have no menu bar item.
    @MainActor
    static func runningApps() -> [App] {
        let own = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.processIdentifier != own && !$0.isTerminated }
            .map { App(pid: $0.processIdentifier, name: $0.localizedName ?? $0.bundleIdentifier ?? "") }
    }

    /// All the items, asked of the apps side by side so the wait is that of the slowest one.
    static func read(_ apps: [App]) async -> [MenuBarEntry] {
        await withTaskGroup(of: [MenuBarEntry].self) { group in
            for app in apps {
                group.addTask { items(of: app) }
            }
            var all: [MenuBarEntry] = []
            for await found in group {
                all += found
            }
            return all
        }
    }

    /// Presses the item again by its place in the app's bar. False when it is gone or the app refuses.
    static func press(_ entry: MenuBarEntry) -> Bool {
        let app = application(entry.pid)
        guard let children = children(of: app), children.indices.contains(entry.index) else { return false }
        let element = children[entry.index]
        // The bar may have changed since it was read: only press what still looks like the same item.
        guard let found = makeEntry(element, App(pid: entry.pid, name: entry.appName), index: entry.index),
              found.title == entry.title
        else { return false }
        return AXUIElementPerformAction(element, "AXPress" as CFString) == .success
    }

    private static func application(_ pid: Int32) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    private static func children(of app: AXUIElement) -> [AXUIElement]? {
        guard let bar = value(app, "AXExtrasMenuBar"), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        let barElement = unsafeDowncast(bar as AnyObject, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(barElement, timeout)
        return value(barElement, "AXChildren") as? [AXUIElement]
    }

    private static func items(of app: App) -> [MenuBarEntry] {
        guard let children = children(of: application(app.pid)) else { return [] }
        return children.enumerated().compactMap { makeEntry($1, app, index: $0) }
    }

    private static func makeEntry(_ element: AXUIElement, _ app: App, index: Int) -> MenuBarEntry? {
        AXUIElementSetMessagingTimeout(element, timeout)
        guard let position = point(element, "AXPosition"), let size = size(element, "AXSize") else { return nil }
        let title = MenuBarEntry.label(
            title: value(element, "AXTitle") as? String,
            description: value(element, "AXDescription") as? String,
            help: value(element, "AXHelp") as? String
        )
        return MenuBarEntry(
            pid: app.pid,
            index: index,
            appName: app.name,
            title: title,
            minX: Double(position.x),
            width: Double(size.width)
        )
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(unsafeDowncast(raw as AnyObject, to: AXValue.self), .cgPoint, &point) ? point : nil
    }

    private static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(unsafeDowncast(raw as AnyObject, to: AXValue.self), .cgSize, &size) ? size : nil
    }
}
