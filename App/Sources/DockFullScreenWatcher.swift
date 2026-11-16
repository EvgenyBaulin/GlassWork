import AppKit
import GlassWorkCore

/// Tells the Dock whether the front app fills the first screen, as an app in full screen does. Reads the window
/// list (bounds and owners only, which need no permission) when the Space or the front app changes.
@MainActor
final class DockFullScreenWatcher {
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var recheck: Task<Void, Never>?

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.changed() }
            }
        }
        check()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        recheck?.cancel()
        recheck = nil
    }

    /// The window list catches up with a Space change a moment later, so it is read now and once more after the
    /// switch has settled.
    private func changed() {
        check()
        recheck?.cancel()
        recheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    private func check() {
        guard let screen = NSScreen.screens.first, let front = NSWorkspace.shared.frontmostApplication else { return }
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let windows = (info as? [[String: Any]] ?? []).compactMap { entry -> DockFullScreen.Window? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return DockFullScreen.Window(pid: pid, layer: layer, bounds: rect)
        }
        // The first screen's top-left corner is the window server's origin.
        onChange(DockFullScreen.covers(
            windows,
            screen: CGRect(origin: .zero, size: screen.frame.size),
            frontPID: front.processIdentifier
        ))
    }
}
