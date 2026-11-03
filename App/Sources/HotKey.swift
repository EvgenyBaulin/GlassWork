import Carbon.HIToolbox

/// Global ⌃⌥Space shortcut.
@MainActor
final class HotKey {
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?

    func register() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.onPress?() }
            return noErr
        }, 1, &type, context, nil)
        let identifier = EventHotKeyID(signature: OSType(0x4757_484B), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
    }
}
