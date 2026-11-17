import GlassWorkCore

extension AppModel {
    /// Keeps the names of accessories that have been seen, so Settings can list them while they are away.
    func rememberDevices() {
        let options = store.settings.module(.deviceBatteries)?.options ?? [:]
        guard let seen = DeviceSelection(options: options).recording(monitor.deviceBatteries) else { return }
        store.update { $0.update(.deviceBatteries) { $0.options[ItemOption.seenDevices] = seen } }
    }

    /// An empty or missing value means the Mac's own pick.
    func applyHardwareChoices() {
        func chosen(_ module: ModuleID, _ key: String) -> String? {
            store.settings.module(module)?.options[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        monitor.networkInterface = chosen(.network, ItemOption.networkInterface)
        monitor.gpuName = chosen(.gpu, ItemOption.gpuName)
        monitor.volumePath = chosen(.disk, ItemOption.volumePath)
    }
}
