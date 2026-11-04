import AppKit
import GlassWorkCore
import SwiftUI

public extension ShortcutAction {
    var title: String {
        switch self {
        case .hub: loc("Open the Hub")
        case .quickPaste: loc("Clipboard history")
        case .textCapture: loc("Copy text from screen")
        case .quickQuit: loc("Quit an app")
        case let .tile(command): command.title
        }
    }
}

extension GlobalShortcut.Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) {
            insert(.control)
        }
        if flags.contains(.option) {
            insert(.option)
        }
        if flags.contains(.shift) {
            insert(.shift)
        }
        if flags.contains(.command) {
            insert(.command)
        }
    }
}

/// Listens for the next key press while a field records, and keeps it from reaching anything else.
@MainActor
final class ShortcutKeyMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping (ShortcutRecording) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = GlobalShortcut.Key(code: Int(event.keyCode))
            let modifiers = GlobalShortcut.Modifiers(event.modifierFlags)
            MainActor.assumeIsolated { handler(ShortcutRecording(key: key, modifiers: modifiers)) }
            return nil
        }
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }
}

/// A shortcut that was pressed but needs an answer first.
struct PendingShortcut: Equatable {
    let action: ShortcutAction
    let shortcut: GlobalShortcut
    let check: ShortcutCheck
}

/// Every global shortcut, each with a field that records a new one.
public struct ShortcutsPane: View {
    private let store: SettingsStore
    private let refused: Set<ShortcutAction>
    private let setRecording: (Bool) -> Void
    @State private var recording: ShortcutAction?
    @State private var pending: PendingShortcut?
    @State private var monitor = ShortcutKeyMonitor()

    /// - Parameter setRecording: Has the app's shortcuts stand down, so the keys reach the field.
    public init(store: SettingsStore, refused: Set<ShortcutAction>, setRecording: @escaping (Bool) -> Void) {
        self.init(store: store, refused: refused, setRecording: setRecording, recording: nil, pending: nil)
    }

    init(
        store: SettingsStore,
        refused: Set<ShortcutAction>,
        setRecording: @escaping (Bool) -> Void,
        recording: ShortcutAction?,
        pending: PendingShortcut?
    ) {
        self.store = store
        self.refused = refused
        self.setRecording = setRecording
        _recording = State(initialValue: recording)
        _pending = State(initialValue: pending)
    }

    private var settings: ShortcutSettings {
        store.settings.shortcuts
    }

    public var body: some View {
        Form {
            Section {
                ForEach([ShortcutAction.hub, .quickPaste, .textCapture, .quickQuit], id: \.self) { row($0) }
            } header: {
                Text(loc("GlassWork"))
            } footer: {
                Text(footer)
            }
            Section(loc("Window Tiles")) {
                ForEach(TileCommand.all.map(ShortcutAction.tile), id: \.self) { row($0) }
            }
            Section(loc("In the app")) {
                LabeledContent(loc("Open Settings"), value: "⌘,")
                LabeledContent(loc("Undo a change in Settings"), value: "⌘Z")
            }
            Section {
                Button(loc("Restore defaults")) {
                    stopRecording()
                    pending = nil
                    store.update { $0.shortcuts.restoreDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
        // A shortcut stands down only while its field is listening: leaving the app must bring them all back.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    private var footer: String {
        if let recording, let current = settings.shortcut(for: recording) {
            return loc("Press the new keys. They need ⌃, ⌥ or ⌘. Esc keeps \(current.label).")
        }
        return loc("Click a field to record. ⌫ clears it, Esc cancels.")
    }

    @ViewBuilder
    private func row(_ action: ShortcutAction) -> some View {
        LabeledContent(action.title) {
            ShortcutField(
                label: fieldLabel(action),
                state: fieldState(action)
            ) {
                toggleRecording(action)
            }
        }
        if let pending, pending.action == action {
            ShortcutBanner(
                pending: pending,
                accept: { accept(pending) },
                cancel: { self.pending = nil }
            )
        }
        if refused.contains(action), let shortcut = settings.shortcut(for: action) {
            Text(loc("Another app already uses \(shortcut.label)."))
                .font(.caption)
                .foregroundStyle(Palette.orange)
        }
    }

    private func fieldLabel(_ action: ShortcutAction) -> String? {
        if let pending, pending.action == action {
            return pending.shortcut.label
        }
        return settings.shortcut(for: action)?.label
    }

    private func fieldState(_ action: ShortcutAction) -> ShortcutField.State {
        if recording == action {
            return .recording
        }
        return pending?.action == action ? .warning : .normal
    }

    private func toggleRecording(_ action: ShortcutAction) {
        pending = nil
        guard recording != action else {
            stopRecording()
            return
        }
        recording = action
        setRecording(true)
        monitor.start { result in
            finish(result, for: action)
        }
    }

    private func stopRecording() {
        monitor.stop()
        recording = nil
        setRecording(false)
    }

    private func finish(_ result: ShortcutRecording, for action: ShortcutAction) {
        stopRecording()
        switch result {
        case .cancel:
            break
        case .clear:
            store.update { $0.shortcuts.set(action, to: nil) }
        case let .record(shortcut):
            let check = ShortcutCheck(shortcut, for: action, in: settings)
            if check == .ok {
                store.update { $0.shortcuts.set(action, to: shortcut) }
            } else {
                pending = PendingShortcut(action: action, shortcut: shortcut, check: check)
            }
        }
    }

    private func accept(_ pending: PendingShortcut) {
        store.update { $0.shortcuts.replace(pending.action, with: pending.shortcut) }
        self.pending = nil
    }
}

/// Shows a shortcut, and asks for one while recording.
struct ShortcutField: View {
    enum State {
        case normal, recording, warning
    }

    let label: String?
    let state: State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                text
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 10)
            .frame(width: 170, height: 24)
            .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: 6))
            .overlay { outline }
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var text: some View {
        switch state {
        case .recording:
            Text(loc("Type shortcut…")).foregroundStyle(.tint)
        case .warning:
            Text(verbatim: label ?? "").foregroundStyle(Palette.orange).font(fieldFont)
        case .normal:
            if let label {
                Text(verbatim: label).font(fieldFont)
            } else {
                Text(loc("Record Shortcut")).foregroundStyle(.tertiary)
            }
        }
    }

    private var fieldFont: Font {
        .system(size: 12, weight: .semibold, design: .monospaced)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .recording: Text(verbatim: "esc").font(.system(size: 10)).foregroundStyle(.secondary)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange)
        case .normal: EmptyView()
        }
    }

    @ViewBuilder
    private var outline: some View {
        switch state {
        case .recording: RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 2)
        case .warning: RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.orange, lineWidth: 2)
        case .normal: EmptyView()
        }
    }
}

/// Why a shortcut was not saved, with the way forward.
struct ShortcutBanner: View {
    let pending: PendingShortcut
    let accept: () -> Void
    let cancel: () -> Void

    private var message: String {
        let label = pending.shortcut.label
        switch pending.check {
        case .needsModifier:
            return loc("\(label) would stop that key from typing. Add ⌃, ⌥ or ⌘.")
        case let .taken(holder):
            return loc("\(label) is already \(holder.title). Replace it?")
        case let .system(name):
            let owner = loc(String.LocalizationValue(name))
            return loc("\(label) is used by \(owner) (macOS). It would stop working there.")
        case .ok:
            return ""
        }
    }

    private var acceptTitle: String? {
        switch pending.check {
        case .needsModifier, .ok: nil
        case .taken: loc("Replace")
        case .system: loc("Use Anyway")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.orange)
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(loc("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
            if let acceptTitle {
                Button(acceptTitle, action: accept)
            }
        }
        .padding(8)
        .background(Palette.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}
