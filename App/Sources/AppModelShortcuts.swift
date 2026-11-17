import GlassWorkCore

extension AppModel {
    /// Both are always wanted: with no keys set, the shortcut centre registers nothing for them.
    func bindFansAndModules() {
        // The same path as the Fans widget button, so it only acts with the helper installed and control on.
        shortcuts.bind(.fansMax) { [weak self] in self?.perform(.toggleFanMax) }
        shortcuts.setActive(.fansMax, true)
        for module in ModuleID.allCases {
            shortcuts.bind(.openModule(module)) { [weak self] in self?.showPanelAtPointer(module) }
            shortcuts.setActive(.openModule(module), true)
        }
    }
}
