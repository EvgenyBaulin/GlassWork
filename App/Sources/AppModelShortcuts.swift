import AppKit
import GlassWorkCore

extension AppModel {
    /// Both are always wanted: with no keys set, the shortcut centre registers nothing for them.
    func bindFansAndModules() {
        // The same path as the Fans widget button, so it only acts with the helper installed and control on.
        shortcuts.bind(.fansMax) { [weak self] in self?.perform(.toggleFanMax) }
        shortcuts.setActive(.fansMax, true)
        // Held only while hiding is on, so the keys stay free otherwise.
        shortcuts.bind(.hiddenBar) { [weak self] in
            guard let self else { return }
            // A shortcut that has Option in it cannot tell whether Option was added on purpose.
            let own = store.settings.shortcuts.shortcut(for: .hiddenBar)?.modifiers ?? []
            let option = NSEvent.modifierFlags.contains(.option) && !own.contains(.option)
            statusBar.toggleHidden(option: option)
        }
        shortcuts.bind(.searchMenuBar) { [weak self] in self?.statusBar.showSearch() }
        shortcuts.setActive(.searchMenuBar, true)
        for module in ModuleID.allCases {
            shortcuts.bind(.openModule(module)) { [weak self] in self?.showPanelAtPointer(module) }
            shortcuts.setActive(.openModule(module), true)
        }
    }
}
