import AppKit
import ApplicationServices
import Carbon.HIToolbox
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Accessibility is needed only to press ⌘V in another app.
@MainActor
enum Accessibility {
    /// Only looks. It never shows a macOS dialog, so it is safe to call from a view.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the macOS dialog. Only the "Paste on click" switch calls this, at the moment it is turned on.
    static func requestAccess() {
        // The literal value of kAXTrustedCheckOptionPrompt, which Swift 6 treats as shared mutable state.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Does nothing without access: an untrusted app must not try to type into others.
    static func pressPaste() {
        guard isTrusted else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

/// The real pasteboard, seen through what capture needs.
@MainActor
private struct SystemPasteboard: PasteboardReading {
    let board: NSPasteboard

    var typeNames: [String] {
        board.types?.map(\.rawValue) ?? []
    }

    func plainText() -> String? {
        board.string(forType: .string)
    }

    func declaredSource() -> String? {
        board.string(forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
    }

    func filePaths() -> [String] {
        guard board.types?.contains(.fileURL) == true else { return [] }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = board.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.map { $0.path(percentEncoded: false) } ?? []
    }

    func colorHex() -> String? {
        guard board.types?.contains(.color) == true,
              let color = NSColor(from: board)?.usingColorSpace(.sRGB)
        else { return nil }
        let channels = [color.redComponent, color.greenComponent, color.blueComponent]
        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    func imagePNG(limit: Int) -> Data? {
        if let png = board.data(forType: .png) {
            return png.count <= limit ? png : nil
        }
        guard let tiff = board.data(forType: .tiff),
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return nil }
        return png.count <= limit ? png : nil
    }
}

/// Watches the pasteboard, puts entries back on it and owns the ⇧⌘V panel.
///
/// Nothing here touches the general pasteboard until recording is turned on: macOS shows an access
/// alert for programmatic reads, so that moment has to be the user's choice.
@MainActor
final class ClipboardController {
    private unowned let model: AppModel
    private let hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: shiftKey | cmdKey, id: 2)
    private var timer: Timer?
    private var lastChange = 0
    private var isWanted = false
    private var isPaused = false
    private var quickPanel: GlassPanel?
    private var dismissal: TransientDismissal?

    /// A copy lasts until the next poll, so a fast second copy is only lost below this interval.
    private static let pollInterval: TimeInterval = 0.5
    /// Long enough for the panel to close and the other app to take the keyboard back.
    private static let pasteDelay = Duration.milliseconds(120)

    private var store: ClipboardStore {
        model.monitor.clipboard
    }

    init(model: AppModel) {
        self.model = model
        hotKey.onPress = { [weak self] in self?.toggleQuickPaste() }
    }

    func apply(_ settings: ClipboardSettings, isEnabled: Bool) {
        isWanted = settings.isRecording && isEnabled
        update()
    }

    /// Nothing is read during sleep, on a locked screen or for another user.
    func setPaused(_ paused: Bool) {
        isPaused = paused
        update()
    }

    private func update() {
        let shouldRun = isWanted && !isPaused
        guard shouldRun != (timer != nil) else { return }
        if shouldRun {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        // What is already there was not copied now, and reading it would raise the alert for no reason.
        lastChange = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        hotKey.register()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        hotKey.unregister()
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        store.isAccessDenied = board.accessBehavior == .alwaysDeny
        guard !store.isAccessDenied else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let app = ClipboardSourceApp(bundleID: front?.bundleIdentifier, name: front?.localizedName)
        if let capture = ClipboardReader.capture(
            from: SystemPasteboard(board: board),
            app: app,
            settings: store.settings,
            at: Date()
        ) {
            store.add(capture)
        }
    }

    /// Copies an entry, then pastes it into the app in front if the user asked for that.
    func use(_ entry: ClipboardEntry, plainText: Bool) {
        write(entry, plainText: plainText)
        model.closePanels()
        closeQuickPaste()
        guard store.settings.pasteOnClick, Accessibility.isTrusted else { return }
        // Pasting right away would land in the panel, which still has the keyboard.
        Task {
            try? await Task.sleep(for: Self.pasteDelay)
            Accessibility.pressPaste()
        }
    }

    private func write(_ entry: ClipboardEntry, plainText: Bool) {
        let board = NSPasteboard.general
        board.clearContents()
        // Only a link has a richer form to give up. Images and files have no plain text to fall back to,
        // and the history keeps text without its formatting, so text is plain either way.
        switch entry.kind {
        case .image:
            if let url = store.imageURL(for: entry), let data = try? Data(contentsOf: url) {
                board.setData(data, forType: .png)
            }
        case .file:
            board.writeObjects(entry.paths.map { URL(filePath: $0) as NSURL })
        case .link where !plainText:
            board.setString(entry.text, forType: .URL)
            board.setString(entry.text, forType: .string)
        default:
            board.setString(entry.text, forType: .string)
        }
        // Without this the next poll would take the app's own write for a new copy.
        lastChange = board.changeCount
    }

    private func toggleQuickPaste() {
        if quickPanel != nil {
            closeQuickPaste()
        } else {
            showQuickPaste()
        }
    }

    private func showQuickPaste() {
        model.closePanels()
        let view = QuickPasteView(
            store: store,
            onUse: { [weak self] in self?.use($0, plainText: false) },
            onCancel: { [weak self] in self?.closeQuickPaste() }
        )
        let hosting = NSHostingView(rootView: view.modifier(PanelGlass()))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        window.setFrame(Self.frame(size: hosting.fittingSize, at: NSEvent.mouseLocation), display: false)
        window.makeKeyAndOrderFront(nil)
        quickPanel = window
        let dismissal = TransientDismissal(panel: window) { [weak self] in self?.closeQuickPaste() }
        dismissal.start()
        self.dismissal = dismissal
    }

    func closeQuickPaste() {
        dismissal?.stop()
        dismissal = nil
        quickPanel?.close()
        quickPanel = nil
    }

    /// Hangs below the cursor and stays on the screen the cursor is on.
    private static func frame(size: CGSize, at cursor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: cursor, size: size)
        let x = min(max(cursor.x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(cursor.y - size.height, visible.minY + 8), visible.maxY - size.height - 8)
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
