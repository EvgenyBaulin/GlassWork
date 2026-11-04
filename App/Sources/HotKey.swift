import Carbon.HIToolbox

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

    func register() {
        guard reference == nil else { return }
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
        RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
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
