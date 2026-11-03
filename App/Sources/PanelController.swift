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
    }
}

/// Liquid Glass tinted so text stays readable over bright wallpapers.
struct PanelGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let tint = scheme == .dark
            ? Color(red: 0.11, green: 0.10, blue: 0.165).opacity(0.55)
            : Color.white.opacity(0.7)
        content.glassEffect(.regular.tint(tint), in: .rect(cornerRadius: 16))
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
    private var outsideClick: Any?
    private var detached: [ModuleID: NSWindow] = [:]
    private var resize: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
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

    func closeTransient() {
        if let outsideClick {
            NSEvent.removeMonitor(outsideClick)
        }
        outsideClick = nil
        if let resize {
            NotificationCenter.default.removeObserver(resize)
        }
        resize = nil
        panel?.close()
        panel = nil
        content = nil
        model.panelsChanged(hasOpenPanel: !detached.isEmpty)
    }

    /// Moves a panel into a floating window that stays until closed.
    func detach(_ module: ModuleID) {
        closeTransient()
        if let window = detached[module] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = ModulePanel(module: module, monitor: model.monitor)
            .environment(\.panelActions, model.actions)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = module.title
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        detached[module] = window
        model.panelsChanged(hasOpenPanel: true)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.detached[module] = nil
                self.model.panelsChanged(hasOpenPanel: self.panel != nil || !self.detached.isEmpty)
            }
        }
    }

    private func toggle(_ new: Content, from button: NSStatusBarButton?, view: () -> AnyView) {
        let wasOpen = content == new
        closeTransient()
        guard !wasOpen else { return }
        show(new, from: button, view: view())
    }

    private func show(_ new: Content, from button: NSStatusBarButton?, view: AnyView) {
        let root = view
            .modifier(PanelGlass())
            .environment(\.panelActions, model.actions)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        let size = hosting.fittingSize
        window.setFrame(frame(size: size, under: button), display: false)
        window.makeKeyAndOrderFront(nil)
        keepTopEdge(of: window)
        panel = window
        content = new
        model.panelsChanged(hasOpenPanel: true)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTransient() }
        }
    }

    /// Panels grow once data arrives; without this they would grow upwards, under the menu bar.
    private func keepTopEdge(of window: GlassPanel) {
        let top = window.frame.maxY
        resize = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            MainActor.assumeIsolated {
                guard let window, window.frame.maxY != top else { return }
                window.setFrameTopLeftPoint(CGPoint(x: window.frame.minX, y: top))
            }
        }
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
