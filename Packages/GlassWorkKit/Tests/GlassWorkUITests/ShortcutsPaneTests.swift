import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

struct ShortcutModifierTests {
    @Test func flagsBecomeModifiers() {
        let modifiers = GlobalShortcut.Modifiers([NSEvent.ModifierFlags.control, .command])
        #expect(modifiers == [.control, .command])
    }

    @Test func otherFlagsAreIgnored() {
        let flags: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function]
        #expect(GlobalShortcut.Modifiers(flags).isEmpty)
    }
}

struct TextCaptureDetailTests {
    @Test func theHintNamesTheShortcutInUse() {
        #expect(TextCaptureNotice.needsScreenRecording.detail(shortcut: "⌃⌥T")?.contains("⌃⌥T") == true)
    }

    @Test func aClearedShortcutIsNotNamed() throws {
        let detail = try #require(TextCaptureNotice.needsScreenRecording.detail(shortcut: nil))
        #expect(!detail.contains("⇧⌘2"))
    }

    @Test func otherNoticesHaveNoHint() {
        #expect(TextCaptureNotice.noText.detail(shortcut: "⌃⌥T") == nil)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct ShortcutsPaneSnapshotTests {
    private func store(_ change: (inout ShortcutSettings) -> Void = { _ in }) -> SettingsStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlassWorkKeys-\(UUID().uuidString)")
        let store = SettingsStore(file: SettingsFile(url: folder.appending(path: "settings.json")))
        store.update { change(&$0.shortcuts) }
        return store
    }

    private func snapshot(
        _ store: SettingsStore,
        name: String,
        dark: Bool,
        refused: Set<ShortcutAction> = [],
        recording: ShortcutAction? = nil,
        pending: PendingShortcut? = nil
    ) {
        let view = ShortcutsPane(
            store: store,
            refused: refused,
            setRecording: { _ in },
            recording: recording,
            pending: pending
        )
        .frame(width: 640, height: 420)
        snapshotPanel(view, name: name, dark: dark)
    }

    @Test(arguments: [true, false])
    func standard(dark: Bool) {
        snapshot(store(), name: "default", dark: dark)
    }

    @Test(arguments: [true, false])
    func recording(dark: Bool) {
        snapshot(store(), name: "recording", dark: dark, recording: .quickQuit)
    }

    @Test(arguments: [true, false])
    func systemClash(dark: Bool) {
        let shortcut = GlobalShortcut([.command], .space)
        let pending = PendingShortcut(action: .quickQuit, shortcut: shortcut, check: .system(name: "Spotlight"))
        snapshot(store(), name: "system", dark: dark, pending: pending)
    }

    @Test(arguments: [true, false])
    func ownClash(dark: Bool) {
        let shortcut = ShortcutAction.hub.defaultShortcut
        let pending = PendingShortcut(action: .quickQuit, shortcut: shortcut, check: .taken(.hub))
        snapshot(store(), name: "own", dark: dark, pending: pending)
    }

    @Test func clearedAndRefused() {
        let store = store { $0.set(.quickPaste, to: nil) }
        snapshot(store, name: "cleared", dark: true, refused: [.quickQuit])
    }
}
