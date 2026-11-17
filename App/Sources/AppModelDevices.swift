import GlassWorkCore

extension AppModel {
    /// Keeps the names of accessories that have been seen, so Settings can list them while they are away.
    func rememberDevices() {
        let options = store.settings.module(.deviceBatteries)?.options ?? [:]
        guard let seen = DeviceSelection(options: options).recording(monitor.deviceBatteries) else { return }
        store.update { $0.update(.deviceBatteries) { $0.options[ItemOption.seenDevices] = seen } }
    }
}
