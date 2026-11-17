import AppKit
import GlassWorkCore

/// Picking a colour from the screen and copying it, for the Colours panel and the menu bar item.
@MainActor
public enum ColourPicking {
    /// Opens the eyedropper. A colour that is picked goes on top of the history and onto the pasteboard.
    public static func pick(
        store: EverydayStore,
        options: [String: String],
        done: @escaping @MainActor () -> Void = {}
    ) {
        NSColorSampler().show { color in
            guard let hex = color?.hexString else { return }
            MainActor.assumeIsolated {
                let limit = options.number(ItemOption.colourLimit, default: EverydayData.colorLimit)
                store.update { $0.addColor(hex, limit: limit) }
                copy(hex, store: store, options: options)
                done()
            }
        }
    }

    /// Puts the colour on the pasteboard in the format chosen in Settings.
    public static func copy(_ hex: String, store: EverydayStore, options: [String: String]) {
        let format = options.choice(ItemOption.colourFormat, default: ColourFormat.hex)
        NSPasteboard.general.clearContents()
        let text = format.text(
            hex: hex,
            isUppercase: options.flag(ItemOption.colourUppercase, default: true),
            hasHash: options.flag(ItemOption.colourHash, default: true)
        )
        NSPasteboard.general.setString(text, forType: .string)
        store.noteColourCopied()
    }
}
