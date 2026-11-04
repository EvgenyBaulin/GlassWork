import AppKit

/// Tells a Dock that hides itself when the pointer moves or a menu opens.
///
/// Mouse monitors need no permission, and exist only while the Dock hides itself. Moves over the app's own windows
/// reach only the local one and moves over any other app only the global one.
@MainActor
final class DockPointerWatcher {
    /// A context menu lies outside the Dock's window, and the Dock must not slide out from under it.
    private(set) var isMenuOpen = false
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    var isWatching: Bool {
        !monitors.isEmpty
    }

    func start() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange() }
        }) {
            monitors.append(outside)
        }
        if let inside = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.onChange() }
            return event
        }) {
            monitors.append(inside)
        }
        let names = [NSMenu.didBeginTrackingNotification, NSMenu.didEndTrackingNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let isOpen = note.name == NSMenu.didBeginTrackingNotification
                MainActor.assumeIsolated {
                    self?.isMenuOpen = isOpen
                    self?.onChange()
                }
            }
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        isMenuOpen = false
    }
}
