import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Borderless glass window that can take keyboard focus without activating the app.
final class GlassPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        canHide = false
    }

    /// Panels grow once data arrives; without this they would grow upwards, under the menu bar.
    func keepTopEdge() -> NSObjectProtocol {
        let top = frame.maxY
        return NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak window = self] _ in
            MainActor.assumeIsolated {
                guard let window, window.frame.maxY != top else { return }
                window.setFrameTopLeftPoint(CGPoint(x: window.frame.minX, y: top))
            }
        }
    }
}

/// Shows module panels and the Hub under the menu bar.
@MainActor
final class PanelController {
    private enum Content: Equatable {
        case module(ModuleID)
        case hub
    }

    private unowned let model: AppModel
    private var panel: GlassPanel?
    private var content: Content?
    private var dismissal: TransientDismissal?
    private lazy var floating = DetachedPanels(model: model)
    private var keyMonitor: Any?
    private var resize: NSObjectProtocol?
    /// The window a card opened from. Clicks on it are left to the card's tile, which toggles the card itself.
    private var anchor: NSWindow?

    init(model: AppModel) {
        self.model = model
        floating.didClose = { [weak self] in
            guard let self else { return }
            self.model.panelsChanged(hasOpenPanel: panel != nil || !floating.isEmpty)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .command, event.charactersIgnoringModifiers == "d" else { return event }
            let window = event.window
            let isHandled = MainActor.assumeIsolated { self?.toggleDetached(in: window) ?? false }
            return isHandled ? nil : event
        }
    }

    /// True while a card opened from this window is showing.
    func hasCard(from window: NSWindow) -> Bool {
        anchor === window
    }

    /// Opens a module's panel as a card of the Dock, or closes it if it is already open.
    ///
    /// - Parameter place: Where the card goes, given its size.
    func toggleCard(_ module: ModuleID, from window: NSWindow, place: (CGSize) -> CGRect) {
        let wasOpen = content == .module(module) && anchor === window
        closeTransient()
        guard !wasOpen else { return }
        anchor = window
        show(.module(module), from: nil, view: AnyView(DockWidgetCard(module: module, monitor: model.monitor)))
        guard let panel else { return }
        panel.setFrame(place(panel.frame.size), display: false)
        // The edge to keep has just moved.
        if let resize {
            NotificationCenter.default.removeObserver(resize)
        }
        resize = panel.keepTopEdge()
    }

    func toggle(_ module: ModuleID, from button: NSStatusBarButton) {
        toggle(.module(module), from: button) {
            AnyView(ModulePanel(module: module, monitor: self.model.monitor))
        }
    }

    func toggleHub(from button: NSStatusBarButton?) {
        toggle(.hub, from: button) {
            AnyView(HubView(monitor: self.model.monitor, store: self.model.store))
        }
    }

    /// Opens a panel next to a desktop widget, on whichever side has room.
    func show(_ module: ModuleID, beside frame: CGRect) {
        closeTransient()
        show(.module(module), from: nil, view: AnyView(ModulePanel(module: module, monitor: model.monitor)))
        guard let panel else { return }
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let right = frame.maxX + 12
        let x = right + panel.frame.width <= visible.maxX ? right : frame.minX - panel.frame.width - 12
        panel.setFrameTopLeftPoint(CGPoint(x: x, y: min(frame.maxY, visible.maxY)))
    }

    func closeTransient() {
        dismissal?.stop()
        dismissal = nil
        if let resize {
            NotificationCenter.default.removeObserver(resize)
        }
        resize = nil
        panel?.close()
        panel = nil
        content = nil
        anchor = nil
        model.panelsChanged(hasOpenPanel: !floating.isEmpty)
    }

    /// Moves a panel into a floating window that stays until closed.
    func detach(_ module: ModuleID) {
        closeTransient()
        floating.open(module)
        model.panelsChanged(hasOpenPanel: true)
    }

    /// Puts a floating window back as the panel under its menu bar item (or the Hub icon, for a module that has none).
    func attach(_ module: ModuleID) {
        floating.close(module)
        let button = model.statusBar.button(for: module) ?? model.statusBar.hubButton
        toggle(.module(module), from: button) {
            AnyView(ModulePanel(module: module, monitor: self.model.monitor))
        }
    }

    /// ⌘D: a floating window goes back under the menu bar, and the open panel becomes a floating window.
    /// Returns whether the key was used.
    private func toggleDetached(in window: NSWindow?) -> Bool {
        if let module = floating.module(of: window) {
            attach(module)
            return true
        }
        if case let .module(module) = content, window === panel {
            detach(module)
            return true
        }
        return false
    }

    private func toggle(_ new: Content, from button: NSStatusBarButton?, view: () -> AnyView) {
        let wasOpen = content == new
        closeTransient()
        guard !wasOpen else { return }
        show(new, from: button, view: view())
    }

    private func show(_ new: Content, from button: NSStatusBarButton?, view: AnyView) {
        model.closeQuickPaste()
        model.closeQuickQuit()
        let root = view
            .modifier(PanelGlass())
            .environment(\.panelActions, model.actions)
            .environment(\.fanControl, model.fans)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        let size = hosting.fittingSize
        window.setFrame(frame(size: size, under: button), display: false)
        window.makeKeyAndOrderFront(nil)
        resize = window.keepTopEdge()
        panel = window
        content = new
        model.panelsChanged(hasOpenPanel: true)
        let dismissal = TransientDismissal(
            panel: window,
            isStatusItem: { [weak self] in
                guard let self else { return false }
                return model.isStatusItem($0) || $0 === anchor
            },
            dismiss: { [weak self] in self?.closeTransient() }
        )
        dismissal.start()
        self.dismissal = dismissal
    }

    /// Centers the panel under its item and keeps it on screen.
    private func frame(size: CGSize, under button: NSStatusBarButton?) -> CGRect {
        let screen = button?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let anchor = button?.window?.frame ?? CGRect(x: visible.maxX - size.width, y: visible.maxY, width: 0, height: 0)
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        return CGRect(x: x, y: visible.maxY - size.height - 6, width: size.width, height: size.height)
    }
}
