import AppKit
import GlassWorkCore
import GlassWorkUI

extension AppModel {
    /// The Colours item: pick a colour on screen, copy it, and show it in the menu bar for a moment.
    func pickColour() {
        panels.closeTransient()
        ColourPicking.pick(
            store: monitor.everyday,
            options: store.settings.module(.colours)?.options ?? [:]
        ) { [weak self] in
            self?.statusBar.refreshItems()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(ItemContent.colourCopiedFlash + 0.1))
                self?.statusBar.refreshItems()
            }
        }
    }

    /// The Hub opened from another item, below that item and not below the Hub's own icon.
    func toggleHub(from button: NSStatusBarButton) {
        statusBar.revealHidden()
        panels.toggleHub(from: button)
    }
}
