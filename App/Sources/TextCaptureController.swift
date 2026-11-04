import AppKit
import Carbon.HIToolbox
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// ⇧⌘2: pick an area of the screen and copy the text in it.
@MainActor
final class TextCaptureController {
    private unowned let model: AppModel
    private let hotKey = HotKey(keyCode: kVK_ANSI_2, modifiers: shiftKey | cmdKey, id: 3)
    private var isCapturing = false
    private var hud: GlassPanel?
    private var hideTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        hotKey.onPress = { [weak self] in self?.start() }
        hotKey.register()
    }

    private func start() {
        guard !isCapturing else { return }
        model.closePanels()
        model.closeQuickPaste()
        // Only looks. The system tool could raise the macOS dialog, so it does not run without access.
        guard CGPreflightScreenCaptureAccess() else {
            show(.needsScreenRecording)
            return
        }
        isCapturing = true
        Task {
            // A picture Vision cannot open holds no text the user can get at.
            let result = await (try? ScreenTextCapture().run()) ?? .noText
            isCapturing = false
            finish(result)
        }
    }

    private func finish(_ result: ScreenTextResult) {
        switch result {
        case .cancelled:
            break
        case .noText:
            show(.noText)
        case let .text(text):
            model.copyToPasteboard(text)
            show(.copied(characters: text.count))
        }
    }

    private func show(_ notice: TextCaptureNotice) {
        hideTask?.cancel()
        hud?.close()
        let hosting = NSHostingView(rootView: TextCaptureHUD(notice: notice).modifier(PanelGlass()))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        window.ignoresMouseEvents = true
        window.setFrame(Self.frame(size: hosting.fittingSize), display: false)
        // Not key: the app the text is going to keeps the keyboard.
        window.orderFrontRegardless()
        hud = window
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: notice.duration)
            guard !Task.isCancelled else { return }
            self?.hud?.close()
            self?.hud = nil
        }
    }

    /// Low on the screen the cursor is on, where the system shows its own volume message.
    private static func frame(size: CGSize) -> CGRect {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        return CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.15,
            width: size.width,
            height: size.height
        )
    }
}
