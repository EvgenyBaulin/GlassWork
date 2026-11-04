import Carbon.HIToolbox
import GlassWorkCore

/// A global shortcut, ⌃⌥Space unless told otherwise.
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

    init(keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey, id: UInt32 = 1) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.id = id
    }

    convenience init(shortcut: GlobalShortcut, id: UInt32) {
        self.init(keyCode: shortcut.key.carbonCode, modifiers: shortcut.modifiers.carbonFlags, id: id)
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

private extension GlobalShortcut.Key {
    var carbonCode: Int {
        switch self {
        case .leftArrow: kVK_LeftArrow
        case .rightArrow: kVK_RightArrow
        case .upArrow: kVK_UpArrow
        case .downArrow: kVK_DownArrow
        case .returnKey: kVK_Return
        case .space: kVK_Space
        case .letterC: kVK_ANSI_C
        case .letterD: kVK_ANSI_D
        case .letterG: kVK_ANSI_G
        case .letterH: kVK_ANSI_H
        case .letterI: kVK_ANSI_I
        case .letterJ: kVK_ANSI_J
        case .letterK: kVK_ANSI_K
        case .letterQ: kVK_ANSI_Q
        case .letterU: kVK_ANSI_U
        case .letterV: kVK_ANSI_V
        case .digit2: kVK_ANSI_2
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
