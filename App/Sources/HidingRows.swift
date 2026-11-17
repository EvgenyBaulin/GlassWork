import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The Hiding section of the Menu Bar page.
struct HidingRows: View {
    let store: SettingsStore

    var body: some View {
        Section(loc("Hiding")) {
            Toggle(loc("Hide items behind a separator"), isOn: binding(\.isEnabled))
            Stepper(value: binding(\.autoHideSeconds), in: 3 ... 60) {
                Text(loc("Hide again after \(store.settings.hiding.autoHideSeconds) s"))
            }
            Toggle(loc("Always-hidden section"), isOn: binding(\.hasAlwaysHidden))
                .disabled(!store.settings.hiding.isEnabled)
            Toggle(loc("Show on hover"), isOn: binding(\.showsOnHover))
                .disabled(!store.settings.hiding.isEnabled)
            Picker(loc("Hover delay"), selection: binding(\.hoverDelay)) {
                ForEach(HiddenBarHoverDelay.allCases, id: \.self) { Text(Self.title($0)).tag($0) }
            }
            .disabled(!store.settings.hiding.isEnabled || !store.settings.hiding.showsOnHover)
            LabeledContent(loc("To remove a macOS item for good, turn it off in System Settings.")) {
                Button(loc("Menu Bar Settings…"), action: Self.openMenuBarSettings)
            }
            Text(loc("""
            Everything left of ‹ hides, macOS items such as Wi-Fi and Battery too. \
            Hold ⌘ and drag an item across ‹ to choose. The clock and Control Center always stay.
            """))
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(loc("""
            With the always-hidden section on, items you ⌘-drag left of the second mark stay hidden when ‹ opens. \
            Option-click ‹, or press the shortcut with Option held, to show them too.
            """))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private static func title(_ delay: HiddenBarHoverDelay) -> String {
        switch delay {
        case .short: loc("0.3 s")
        case .medium: loc("0.6 s")
        case .long: loc("1 s")
        }
    }

    private func binding<Value>(_ path: WritableKeyPath<HidingSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings.hiding[keyPath: path] },
            set: { value in store.update { $0.hiding[keyPath: path] = value } }
        )
    }

    /// Only opens the page: which macOS items are shown stays the user's change to make there.
    private static func openMenuBarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
