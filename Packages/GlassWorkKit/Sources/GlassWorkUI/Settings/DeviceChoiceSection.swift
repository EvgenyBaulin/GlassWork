import GlassWorkCore
import SwiftUI

/// The accessories seen so far, for choosing which ones count towards the menu bar figure.
public struct DeviceChoiceSection: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    private var selection: DeviceSelection {
        DeviceSelection(options: store.settings.module(.deviceBatteries)?.options ?? [:])
    }

    public var body: some View {
        DeviceChoices(selection: selection) { name, isIncluded in
            let value = selection.stored(after: name, isIncluded: isIncluded)
            store
                .update {
                    $0.update(.deviceBatteries) { $0.options[ItemOption.excludedDevices] = value.isEmpty ? nil : value }
                }
        }
    }
}

struct DeviceChoices: View {
    let selection: DeviceSelection
    let change: (String, Bool) -> Void

    var body: some View {
        Section {
            if selection.seen.isEmpty {
                Text(loc("Devices appear here once they have been connected. All are included until then."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selection.seen, id: \.self) { name in
                    Toggle(
                        isOn: Binding(get: { selection.includes(name) }, set: { change(name, $0) })
                    ) {
                        Text(verbatim: name)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        } header: {
            Text(loc("Devices in the menu bar"))
        } footer: {
            Text(loc("The menu bar shows the lowest charge among the ticked devices."))
        }
    }
}
