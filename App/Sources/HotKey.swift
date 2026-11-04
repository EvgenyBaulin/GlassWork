import Carbon.HIToolbox
import GlassWorkCore
import Observation

/// A global shortcut.
///
/// Carbon offers every press to every installed handler, newest first, so each shortcut has its own id
/// and passes on the presses that are not its own.
@MainActor
final class HotKey {
    var onPress: (() -> Void)?
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let id: UInt32
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(shortcut: GlobalShortcut, id: UInt32) {
        keyCode = UInt32(shortcut.key.code)
        modifiers = UInt32(shortcut.modifiers.carbonFlags)
        self.id = id
    }

    /// False when macOS refuses the shortcut, which means another app already holds it.
    @discardableResult
    func register() -> Bool {
        guard reference == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressed
            )
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                hotKey.onPress?()
                return noErr
            }
        }, 1, &type, context, &handler)
        let identifier = EventHotKeyID(signature: OSType(0x4757_484B), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        guard status != noErr else { return true }
        unregister()
        return false
    }

    func unregister() {
        if let reference {
            UnregisterEventHotKey(reference)
        }
        if let handler {
            RemoveEventHandler(handler)
        }
        reference = nil
        handler = nil
    }
}

/// Every global shortcut in one place. Features say what a shortcut does and when they want it; which keys that
/// is comes from settings, so a change in Settings applies at once.
@MainActor
@Observable
final class ShortcutCenter {
    /// Actions macOS would not give their shortcut to, because another app holds it.
    private(set) var refused: Set<ShortcutAction> = []

    @ObservationIgnored var onRefused: ((ShortcutAction) -> Void)?
    @ObservationIgnored private var handlers: [ShortcutAction: () -> Void] = [:]
    @ObservationIgnored private var wanted: Set<ShortcutAction> = []
    @ObservationIgnored private var settings = ShortcutSettings()
    @ObservationIgnored private var registered: [ShortcutAction: (shortcut: GlobalShortcut, hotKey: HotKey)] = [:]
    @ObservationIgnored private var isRecording = false

    func bind(_ action: ShortcutAction, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    /// Takes the shortcut from macOS while `isActive`, and gives it back otherwise.
    func setActive(_ action: ShortcutAction, _ isActive: Bool) {
        if isActive {
            wanted.insert(action)
        } else {
            wanted.remove(action)
        }
        update()
    }

    func apply(_ settings: ShortcutSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        update()
    }

    /// A registered shortcut reaches its handler before any window sees the key, so the recorder would never
    /// get it. All of them stand down while one is being recorded.
    func setRecording(_ value: Bool) {
        guard value != isRecording else { return }
        isRecording = value
        update()
    }

    private func update() {
        let target = isRecording ? [:] : targets
        if !isRecording {
            // An action that no longer wants its keys has nothing left to warn about.
            refused = refused.filter { target[$0] != nil }
        }
        for (action, entry) in registered where target[action] != entry.shortcut {
            entry.hotKey.unregister()
            registered[action] = nil
        }
        for (action, shortcut) in target where registered[action] == nil {
            register(action, shortcut)
        }
    }

    private var targets: [ShortcutAction: GlobalShortcut] {
        var result: [ShortcutAction: GlobalShortcut] = [:]
        for action in wanted {
            result[action] = settings.shortcut(for: action)
        }
        return result
    }

    private func register(_ action: ShortcutAction, _ shortcut: GlobalShortcut) {
        // The id only has to stay the same for as long as the shortcut is registered.
        let id = UInt32((ShortcutAction.all.firstIndex(of: action) ?? 0) + 1)
        let hotKey = HotKey(shortcut: shortcut, id: id)
        hotKey.onPress = { [weak self] in self?.handlers[action]?() }
        if hotKey.register() {
            registered[action] = (shortcut, hotKey)
            refused.remove(action)
        } else if refused.insert(action).inserted {
            onRefused?(action)
        }
    }
}

private extension GlobalShortcut.Modifiers {
    var carbonFlags: Int {
        var flags = 0
        if contains(.control) {
            flags |= controlKey
        }
        if contains(.option) {
            flags |= optionKey
        }
        if contains(.shift) {
            flags |= shiftKey
        }
        if contains(.command) {
            flags |= cmdKey
        }
        return flags
    }
}
