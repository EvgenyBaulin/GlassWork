import GlassWorkCore
import GlassWorkUI
import SwiftUI

struct WidgetsPane: View {
    let store: SettingsStore
    @State private var kind = WidgetKind.activity
    @State private var size = WidgetSize.medium
    @State private var commandName = ""
    @State private var commandText = ""
    @State private var endpointText = ""

    var body: some View {
        Form {
            Section {
                Text(loc("Right-click the desktop and choose Edit Widgets to add system widgets."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("System widgets"))
            }
            Section(loc("Live desktop widgets")) {
                ForEach(store.settings.widgets.placements) { placement in
                    HStack {
                        Text(placement.kind.title)
                        Spacer()
                        Button(loc("Remove")) {
                            store.update { $0.widgets.placements.removeAll { $0.id == placement.id } }
                        }
                    }
                }
                Picker(loc("Widget"), selection: $kind) {
                    ForEach(WidgetKind.gallery) { Text($0.title).tag($0) }
                }
                Picker(loc("Size"), selection: $size) {
                    Text("S").tag(WidgetSize.small)
                    Text("M").tag(WidgetSize.medium)
                    Text("L").tag(WidgetSize.large)
                    Text("XL").tag(WidgetSize.extraLarge)
                }
                .pickerStyle(.segmented)
                Button(loc("Add Widget")) { add() }
            }
            Section(loc("Screen Time")) {
                Toggle(loc("Track which app is in front"), isOn: Binding(
                    get: { store.settings.widgets.tracksScreenTime },
                    set: { value in store.update { $0.widgets.tracksScreenTime = value } }
                ))
                Text(loc("Stored only on this Mac for 30 days."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(loc("Commands")) {
                ForEach(store.settings.widgets.commands) { command in
                    LabeledContent(command.name, value: command.command)
                }
                HStack {
                    TextField(loc("Name"), text: $commandName)
                    TextField(loc("Command"), text: $commandText)
                    Button(loc("Add")) {
                        guard !commandName.isEmpty, !commandText.isEmpty else { return }
                        let command = UserCommand(name: commandName, command: commandText)
                        store.update { $0.widgets.commands.append(command) }
                        commandName = ""
                        commandText = ""
                    }
                }
            }
            Section(loc("Endpoints")) {
                ForEach(store.settings.widgets.endpoints) { endpoint in
                    Text(endpoint.url.absoluteString)
                }
                HStack {
                    TextField("https://", text: $endpointText)
                    Button(loc("Add")) {
                        guard let url = URL(string: endpointText), url.scheme != nil else { return }
                        store.update { $0.widgets.endpoints.append(Endpoint(url: url)) }
                        endpointText = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let visible = NSScreen.main?.visibleFrame ?? .zero
        let count = Double(store.settings.widgets.placements.count)
        let x = visible.minX + 24 + count * WidgetPlacement.gridStep
        let y = visible.maxY - 24 - size.height
        store.update { $0.widgets.placements.append(WidgetPlacement(kind: kind, size: size, x: x, y: y)) }
    }
}

struct DockPane: View {
    let store: SettingsStore
    @State private var confirming = false

    private var dock: AppSettingsBinding {
        AppSettingsBinding(store: store)
    }

    var body: some View {
        Form {
            Section {
                Toggle(loc("Use GlassWork Dock"), isOn: Binding(
                    get: { store.settings.dock.isEnabled },
                    set: { value in
                        if value {
                            confirming = true
                        } else {
                            store.update { $0.dock.isEnabled = false }
                        }
                    }
                ))
                Text(
                    loc("The system Dock is hidden while GlassWork Dock runs, and comes back as it was when you quit.")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section(loc("Size")) {
                Slider(value: dock.iconSize, in: 32 ... 96) { Text(loc("Icon size")) }
                Toggle(loc("Magnification"), isOn: dock.magnifies)
                Slider(value: dock.magnifiedSize, in: 48 ... 128) { Text(loc("Magnified size")) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(loc("Use GlassWork Dock?"), isPresented: $confirming) {
            Button(loc("Use GlassWork Dock")) {
                store.update { settings in
                    if settings.dock.items.isEmpty {
                        settings.dock.items = SystemDockApps.read().map(DockItem.app)
                    }
                    settings.dock.isEnabled = true
                }
            }
        }
    }
}

/// Bindings into Dock settings.
@MainActor
struct AppSettingsBinding {
    let store: SettingsStore

    var iconSize: Binding<Double> {
        Binding(get: { store.settings.dock.iconSize }, set: { value in store.update { $0.dock.iconSize = value } })
    }

    var magnifies: Binding<Bool> {
        Binding(get: { store.settings.dock.magnifies }, set: { value in store.update { $0.dock.magnifies = value } })
    }

    var magnifiedSize: Binding<Double> {
        Binding(
            get: { store.settings.dock.magnifiedSize },
            set: { value in store.update { $0.dock.magnifiedSize = value } }
        )
    }
}

struct ShortcutsPane: View {
    var body: some View {
        Form {
            Section(loc("Shortcuts")) {
                LabeledContent(loc("Open the Hub"), value: "⌃⌥Space")
                LabeledContent(loc("Open Settings"), value: "⌘,")
                LabeledContent(loc("Undo a change in Settings"), value: "⌘Z")
            }
        }
        .formStyle(.grouped)
    }
}
