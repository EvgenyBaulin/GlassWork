import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

extension DisplayInfo {
    init?(_ screen: NSScreen) {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        self.init(id: number.uint32Value, name: screen.localizedName, visibleFrame: screen.visibleFrame)
    }

    /// The display the pointer is on, else the main one.
    @MainActor
    static var underPointer: DisplayInfo? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen.flatMap(DisplayInfo.init)
    }
}

/// Floating module windows: resizable, remembered per module and display, and able to go back under the menu bar.
@MainActor
final class DetachedPanels {
    private unowned let model: AppModel
    private var windows: [ModuleID: NSWindow] = [:]
    private var observers: [ModuleID: [NSObjectProtocol]] = [:]
    private var saves: [ModuleID: Task<Void, Never>] = [:]
    /// Called after a window has closed, so the owner can update the demand for live data.
    var didClose: () -> Void = {}

    /// Wait for a drag or a resize to settle before writing the settings file.
    private static let saveDelay = Duration.milliseconds(500)
    /// A new window never opens taller than this, whatever the panel says.
    private static let initialHeightLimit: CGFloat = 700

    init(model: AppModel) {
        self.model = model
    }

    var isEmpty: Bool {
        windows.isEmpty
    }

    func module(of window: NSWindow?) -> ModuleID? {
        guard let window else { return nil }
        return windows.first { $0.value === window }?.key
    }

    func open(_ module: ModuleID) {
        if let window = windows[module] {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = makeWindow(module)
        windows[module] = window
        observe(window, module: module)
        window.makeKeyAndOrderFront(nil)
    }

    /// Closes the window of a module, if it has one.
    func close(_ module: ModuleID) {
        windows[module]?.close()
    }

    private func makeWindow(_ module: ModuleID) -> NSWindow {
        let panel = ModulePanel(module: module, monitor: model.monitor)
            .environment(\.panelActions, model.actions)
            .environment(\.fanControl, model.fans)
        // The size the panel asks for under the menu bar is where a new window starts.
        let natural = NSHostingView(rootView: panel).fittingSize
        let scrolling = ScrollView(.vertical) {
            panel
                .environment(\.panelDetached, true)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        let hosting = NSHostingView(rootView: scrolling)
        // The window is resized by the person, not by the content.
        hosting.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: natural),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.title = module.title
        window.titlebarAppearsTransparent = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.contentMinSize = DetachedPanelMemory.minimumSize
        window.contentMaxSize = DetachedPanelMemory.maximumSize
        place(window, module: module, natural: natural)
        return window
    }

    private func place(_ window: NSWindow, module: ModuleID, natural: CGSize) {
        guard let preferred = DisplayInfo.underPointer else {
            window.center()
            return
        }
        let displays = NSScreen.screens.compactMap(DisplayInfo.init)
        if let saved = model.store.settings.detachedPanels
            .frame(for: module, preferred: preferred, displays: displays)
        {
            window.setFrame(saved, display: false)
            return
        }
        let size = CGSize(width: natural.width, height: min(natural.height, Self.initialHeightLimit))
        let fitted = DetachedPanelMemory.clamp(CGRect(origin: .zero, size: size), to: preferred.visibleFrame)
        window.setFrame(fitted, display: false)
        window.center()
    }

    private func observe(_ window: NSWindow, module: ModuleID) {
        let center = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleSave(module) }
            })
        }
        let willClose = NSWindow.willCloseNotification
        tokens.append(center.addObserver(forName: willClose, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closed(module) }
        })
        observers[module] = tokens
    }

    private func scheduleSave(_ module: ModuleID) {
        saves[module]?.cancel()
        saves[module] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.remember(module)
        }
    }

    /// Saves every pending frame now, for quitting before the delay has passed.
    func flush() {
        for module in Array(saves.keys) {
            saves[module]?.cancel()
            saves[module] = nil
            remember(module)
        }
    }

    private func remember(_ module: ModuleID) {
        guard let window = windows[module], let screen = window.screen,
              let display = DisplayInfo(screen) else { return }
        let frame = window.frame
        guard !model.store.settings.detachedPanels.isCurrent(module, frame: frame, on: display) else { return }
        // Window positions are not settings changes: they stay out of undo and redo.
        model.store.update(undoable: false) {
            $0.detachedPanels.remember(module, frame: frame, on: display, at: Date())
        }
    }

    private func closed(_ module: ModuleID) {
        saves[module]?.cancel()
        saves[module] = nil
        remember(module)
        for token in observers[module] ?? [] {
            NotificationCenter.default.removeObserver(token)
        }
        observers[module] = nil
        windows[module] = nil
        didClose()
    }
}
