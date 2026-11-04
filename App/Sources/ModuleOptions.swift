import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The sections a module adds to its Settings page.
struct ModuleOptions: View {
    let module: ModuleID
    let store: SettingsStore

    var body: some View {
        switch module {
        case .weather: WeatherOptions(store: store)
        case .rates: RatesOptions(store: store)
        case .clipboard: ClipboardOptions(store: store)
        case _ where ModuleID.developerCollected.contains(module):
            DeveloperOptionsSection(module: module, store: store)
        default: EmptyView()
        }
    }
}

private struct WeatherOptions: View {
    let store: SettingsStore

    private var useLocation: Binding<Bool> {
        Binding(
            get: { store.settings.weather.useCurrentLocation },
            set: { value in store.update { $0.weather.useCurrentLocation = value } }
        )
    }

    var body: some View {
        Section(loc("Weather")) {
            Toggle(loc("Use current location"), isOn: useLocation)
            Text(loc("macOS asks for access when this is turned on. Cities are managed in the panel."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RatesOptions: View {
    let store: SettingsStore

    private var isMonochrome: Binding<Bool> {
        Binding(
            get: { store.settings.rates.isMonochrome },
            set: { value in store.update { $0.rates.isMonochrome = value } }
        )
    }

    var body: some View {
        Section(loc("Rates")) {
            Toggle(loc("Monochrome day change in the menu bar"), isOn: isMonochrome)
        }
    }
}

private struct ClipboardOptions: View {
    let store: SettingsStore
    @State private var newApp = ""

    private func binding<Value>(_ path: WritableKeyPath<ClipboardSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings.clipboard[keyPath: path] },
            set: { value in store.update { $0.clipboard[keyPath: path] = value } }
        )
    }

    /// The only place that asks macOS for Accessibility, and only when the switch goes on.
    private var pasteOnClick: Binding<Bool> {
        Binding(
            get: { store.settings.clipboard.pasteOnClick },
            set: { value in
                store.update { $0.clipboard.pasteOnClick = value }
                if value, !Accessibility.isTrusted {
                    Accessibility.requestAccess()
                }
            }
        )
    }

    var body: some View {
        Section(loc("History")) {
            Toggle(loc("Keep a clipboard history"), isOn: binding(\.isRecording))
            Stepper(value: binding(\.retentionDays), in: 1 ... 365) {
                Text(loc("Keep for \(store.settings.clipboard.retentionDays) days"))
            }
            Toggle(loc("Show the last item in the menu bar"), isOn: binding(\.showsLastItem))
            Text(loc("Stored on this Mac, not encrypted. Pinned items are kept until you delete them."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section(loc("Paste")) {
            Toggle(loc("Paste on click"), isOn: pasteOnClick)
            if store.settings.clipboard.pasteOnClick, !Accessibility.isTrusted {
                LabeledContent(loc("Needs Accessibility")) {
                    Button(loc("Open System Settings")) { Accessibility.openSettings() }
                }
            }
        }
        Section(loc("Never record from these apps")) {
            ForEach(store.settings.clipboard.excludedApps, id: \.self) { app in
                HStack {
                    Text(app).font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button(loc("Remove")) {
                        store.update { $0.clipboard.excludedApps.removeAll { $0 == app } }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField(loc("Bundle identifier"), text: $newApp).onSubmit(addApp)
                Button(loc("Add"), action: addApp).disabled(newApp.isEmpty)
            }
        }
    }

    private func addApp() {
        let app = newApp.trimmingCharacters(in: .whitespaces)
        guard !app.isEmpty, !store.settings.clipboard.excludedApps.contains(app) else { return }
        store.update { $0.clipboard.excludedApps.append(app) }
        newApp = ""
    }
}
