import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The palette that quits an app from anywhere.
@MainActor
final class QuickQuitController {
    private unowned let model: AppModel
    private var panel: GlassPanel?
    private var state: QuickQuitState?
    private var dismissal: TransientDismissal?
    private var keys: Any?
    private var resize: NSObjectProtocol?

    /// Where the top of the palette sits, as a share of the screen's height from the bottom.
    private static let height = 0.72

    init(model: AppModel) {
        self.model = model
        model.shortcuts.bind(.quickQuit) { [weak self] in self?.toggle() }
        model.shortcuts.setActive(.quickQuit, true)
    }

    private func toggle() {
        if panel != nil {
            close()
        } else {
            show()
        }
    }

    private func show() {
        model.closePanels()
        model.closeQuickPaste()
        let state = QuickQuitState(store: model.monitor.apps) { [weak self] app, force in
            self?.close()
            self?.model.quit(app.target, force: force)
        }
        let hosting = NSHostingView(rootView: QuickQuitView(state: state).modifier(PanelGlass()))
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
        model.quickQuitChanged(isOpen: true)
    }

    func close() {
        guard panel != nil else { return }
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
        model.quickQuitChanged(isOpen: false)
    }

    /// Taken before the text field, which would keep the arrows and turn ⌥Return into a line break.
    private func watchKeys() {
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let isOptionDown = event.modifierFlags.contains(.option)
            let window = event.window
            let isHandled = MainActor.assumeIsolated {
                guard let self, window === self.panel,
                      let key = QuickQuitKey(keyCode: keyCode, isOptionDown: isOptionDown)
                else { return false }
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
