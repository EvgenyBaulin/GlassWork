import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The panel that finds another app's menu bar item and opens it. The list is read when the panel opens and never
/// again, so nothing runs in the background.
@MainActor
final class MenuBarSearchController {
    /// Where the separators are, as the status bar reports it.
    struct Geometry {
        var separatorMaxX: Double?
        var alwaysHiddenMaxX: Double?
    }

    private unowned let model: AppModel
    private let geometry: () -> Geometry
    private let reveal: (Bool) -> Void
    private var panel: GlassPanel?
    private var state: MenuBarSearchState?
    private var dismissal: TransientDismissal?
    private var keys: Any?
    private var resize: NSObjectProtocol?
    private var loading: Task<Void, Never>?

    /// Where the top of the panel sits, as a share of the screen's height from the bottom.
    private static let height = 0.72
    /// How long the bar takes to slide open, before the item is pressed.
    private static let settle = Duration.milliseconds(300)

    init(model: AppModel, geometry: @escaping () -> Geometry, reveal: @escaping (Bool) -> Void) {
        self.model = model
        self.geometry = geometry
        self.reveal = reveal
    }

    func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    func show() {
        close()
        model.closePanels()
        model.closeQuickPaste()
        model.closeQuickQuit()
        let isTrusted = Accessibility.isTrusted
        let state = MenuBarSearchState(
            phase: isTrusted ? .loading : .needsAccess,
            icon: { NSRunningApplication(processIdentifier: $0.pid)?.icon },
            onActivate: { [weak self] in self?.activate($0) },
            onOpenSettings: { [weak self] in
                self?.close()
                Accessibility.openSettings()
            }
        )
        let hosting = NSHostingView(rootView: MenuBarSearchView(state: state).modifier(PanelGlass()))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        window.setFrame(Self.frame(size: hosting.fittingSize), display: false)
        window.makeKeyAndOrderFront(nil)
        resize = window.keepTopEdge()
        panel = window
        self.state = state
        let dismissal = TransientDismissal(panel: window) { [weak self] in self?.close() }
        dismissal.start()
        self.dismissal = dismissal
        watchKeys()
        if isTrusted {
            load(into: state)
        }
    }

    func close() {
        guard panel != nil else { return }
        loading?.cancel()
        loading = nil
        dismissal?.stop()
        dismissal = nil
        if let keys {
            NSEvent.removeMonitor(keys)
        }
        keys = nil
        if let resize {
            NotificationCenter.default.removeObserver(resize)
        }
        resize = nil
        panel?.close()
        panel = nil
        state = nil
    }

    private func load(into state: MenuBarSearchState) {
        let apps = MenuBarInventory.runningApps()
        loading = Task { [weak self] in
            let entries = await MenuBarInventory.read(apps)
            guard !Task.isCancelled, let self else { return }
            let place = geometry()
            state.load(entries, separatorMaxX: place.separatorMaxX, alwaysHiddenMaxX: place.alwaysHiddenMaxX)
        }
    }

    /// Opens the section the item is in, then presses it. If pressing fails the bar is still open on it.
    private func activate(_ entry: MenuBarEntry) {
        let section = state?.section(of: entry) ?? .visible
        close()
        if section != .visible {
            reveal(section == .alwaysHidden)
        }
        Task.detached {
            if section != .visible {
                try? await Task.sleep(for: Self.settle)
            }
            _ = MenuBarInventory.press(entry)
        }
    }

    /// Taken before the text field, which would keep the arrows.
    private func watchKeys() {
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let window = event.window
            let isHandled = MainActor.assumeIsolated {
                guard let self, window === self.panel,
                      let key = MenuBarSearchKey(keyCode: keyCode) else { return false }
                self.state?.handle(key)
                return true
            }
            return isHandled ? nil : event
        }
    }

    /// Centered in the upper part of the screen the pointer is on, which is where the eyes already are.
    private static func frame(size: CGSize) -> CGRect {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: cursor, size: size)
        let top = visible.minY + visible.height * height
        return CGRect(x: visible.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
    }
}
