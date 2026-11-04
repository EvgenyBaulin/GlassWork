import GlassWorkCore
import GlassWorkUI
import SwiftUI

struct WidgetsPane: View {
    let store: SettingsStore
    let personal: PersonalWidgetStore
    let activity: ActivityStore
    @State private var kind = WidgetKind.activity
    @State private var size = WidgetSize.medium
    @State private var endpointText = ""

    var body: some View {
        Form {
            Section {
                Text(loc("Right-click the desktop and choose Edit Widgets to add system widgets."))
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("System widgets"))
            }
            PersonalWidgetsSection(store: store, personal: personal)
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
            CommandsSection(store: store, activity: activity)
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
    @State private var isExplaining = false

    private var dock: AppSettingsBinding {
        AppSettingsBinding(store: store)
    }

    var body: some View {
        Form {
            Section {
                Toggle(loc("Use GlassWork Dock"), isOn: Binding(
                    get: { store.settings.dock.isEnabled },
                    set: { value in
                        if !value {
                            store.update { $0.dock.isEnabled = false }
                        } else if store.settings.dock.hasSeenIntro {
                            enable()
                        } else {
                            isExplaining = true
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
            Section(loc("Position")) {
                Picker(loc("Position on screen"), selection: dock.position) {
                    ForEach(DockPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle(loc("Automatically hide and show"), isOn: dock.autoHides)
            }
            widgetsSection
            stacksSection
            presetsSection
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isExplaining) {
            DockFirstRunView(
                proceed: {
                    isExplaining = false
                    enable()
                },
                cancel: { isExplaining = false }
            )
        }
    }

    private func enable() {
        store.update { $0.dock.enable(importing: SystemDockApps.read) }
    }
}

private extension DockPane {
    var widgets: [ModuleID] {
        store.settings.dock.widgets
    }

    func setWidgets(_ widgets: [ModuleID]) {
        store.update { $0.dock.items = DockLayout.setting(widgets: widgets, in: $0.dock.items) }
    }

    var widgetsSection: some View {
        Section {
            ForEach(widgets) { module in
                HStack {
                    Text(module.title)
                    Spacer()
                    Text(module.dockClickTitle).font(.caption).foregroundStyle(.secondary)
                    Button(loc("Remove")) { setWidgets(widgets.filter { $0 != module }) }
                }
            }
            .onMove { source, destination in
                var moved = widgets
                moved.move(fromOffsets: source, toOffset: destination)
                setWidgets(moved)
            }
            Menu(loc("Add Widget")) {
                ForEach(ModuleID.dockWidgets.filter { !widgets.contains($0) }) { module in
                    Button(module.title) { setWidgets(widgets + [module]) }
                }
            }
        } header: {
            Text(loc("Widgets in Dock"))
        } footer: {
            Text(loc("Click runs the quick action, hold opens the widget as a card above the Dock."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension DockPane {
    var presets: [DockPreset] {
        DockPresets.offered(in: store.settings.dock)
    }

    func use(_ preset: DockPreset) {
        let current = presets.first { $0.id == store.settings.dock.activePreset }
        store.update { DockPresets.apply(preset, current: current, to: &$0.dock) }
    }

    func presetRow(_ preset: DockPreset) -> some View {
        let dock = store.settings.dock
        let isActive = dock.activePreset == preset.id
        return HStack {
            VStack(alignment: .leading) {
                Text(preset.title)
                Text(loc("\(preset.widgets.count) widgets")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text(loc("In use")).font(.caption).foregroundStyle(Palette.blue)
                Button(loc("Save Changes")) {
                    store.update { settings in
                        let saved = DockPresets.capture(settings.dock, id: preset.id, name: preset.name)
                        DockPresets.store(saved, in: &settings.dock)
                    }
                }
            } else {
                Button(loc("Use")) { use(preset) }
            }
            if !preset.isBuiltIn {
                Button(loc("Delete")) { store.update { DockPresets.remove(preset, from: &$0.dock) } }
            } else if DockPresets.isEdited(preset, in: dock) {
                Button(loc("Restore Original")) { store.update { DockPresets.remove(preset, from: &$0.dock) } }
            }
        }
    }

    var presetsSection: some View {
        Section {
            ForEach(presets) { presetRow($0) }
        } header: {
            Text(loc("Presets"))
        } footer: {
            Text(loc("A preset changes widgets and its own folders. Your apps and stacks stay."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension DockPane {
    func add(_ stack: DockStack) {
        store.update { $0.dock.items = DockLayout.adding(stack, to: $0.dock.items) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(DockStack(path: url.path(percentEncoded: false), name: url.lastPathComponent))
    }

    /// Adding Downloads here is the only thing that makes the app read it.
    var stacksSection: some View {
        Section {
            ForEach(store.settings.dock.stacks) { stack in
                HStack {
                    Text(stack.name)
                    Spacer()
                    if !stack.isDownloads {
                        Picker(loc("Display as"), selection: Binding(
                            get: { stack.style },
                            set: { style in
                                store.update { $0.dock.items = DockLayout.setting(style, of: stack, in: $0.dock.items) }
                            }
                        )) {
                            ForEach(DockStackStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Button(loc("Remove")) {
                        store.update { $0.dock.items = DockLayout.removing(.stack(stack), from: $0.dock.items) }
                    }
                }
            }
            HStack {
                Button(loc("Add Downloads")) { add(.downloads(name: loc("Downloads"))) }
                    .disabled(store.settings.dock.stacks.contains(where: \.isDownloads))
                Button(loc("Add Folder…")) { chooseFolder() }
            }
        } header: {
            Text(loc("Stacks"))
        } footer: {
            Text(loc("macOS may ask for access to a folder when you add it."))
                .font(.caption)
                .foregroundStyle(.secondary)
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

    var position: Binding<DockPosition> {
        Binding(get: { store.settings.dock.position }, set: { value in store.update { $0.dock.position = value } })
    }

    var autoHides: Binding<Bool> {
        Binding(get: { store.settings.dock.autoHides }, set: { value in store.update { $0.dock.autoHides = value } })
    }
}
