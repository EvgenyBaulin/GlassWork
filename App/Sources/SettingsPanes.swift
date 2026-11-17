import GlassWorkCore
import GlassWorkUI
import SwiftUI

struct WidgetsPane: View {
    let store: SettingsStore
    let personal: PersonalWidgetStore
    let activity: ActivityStore
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
                    EndpointEditor(endpoint: endpoint) { change in
                        store.update { settings in
                            guard let index = settings.widgets.endpoints.firstIndex(where: { $0.id == endpoint.id })
                            else { return }
                            if let change {
                                settings.widgets.endpoints[index] = change
                            } else {
                                settings.widgets.endpoints.remove(at: index)
                            }
                        }
                    }
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
}

/// One watched address: its URL, how often and how it is checked. `nil` from `onChange` removes it.
private struct EndpointEditor: View {
    let endpoint: Endpoint
    let onChange: (Endpoint?) -> Void
    @State private var isOpen = false
    @State private var urlText: String

    private static let intervals: [TimeInterval] = [10, 30, 60, 300, 900, 3600]

    init(endpoint: Endpoint, onChange: @escaping (Endpoint?) -> Void) {
        self.endpoint = endpoint
        self.onChange = onChange
        _urlText = State(initialValue: endpoint.url.absoluteString)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            TextField(loc("Address"), text: $urlText)
                .onSubmit(commitURL)
            Picker(loc("Check every"), selection: edit(\.interval)) {
                ForEach(intervalChoices, id: \.self) { Text(Self.title(seconds: $0)).tag($0) }
            }
            Picker(loc("Method"), selection: edit(\.method)) {
                ForEach(EndpointMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Stepper(value: edit(\.expectedStatus), in: 100 ... 599) {
                LabeledContent(loc("Expected status"), value: String(endpoint.expectedStatus))
            }
            Stepper(value: edit(\.timeout), in: Endpoint.timeoutRange, step: 1) {
                LabeledContent(loc("Timeout"), value: loc("\(Int(endpoint.timeout)) s"))
            }
            Button(loc("Remove"), role: .destructive) { onChange(nil) }
        } label: {
            Text(endpoint.url.absoluteString).lineLimit(1).truncationMode(.middle)
        }
    }

    /// A saved interval outside the list stays selectable.
    private var intervalChoices: [TimeInterval] {
        Self.intervals.contains(endpoint.interval) ? Self.intervals : (Self.intervals + [endpoint.interval]).sorted()
    }

    private static func title(seconds: TimeInterval) -> String {
        seconds < 60 ? loc("\(Int(seconds)) s") : loc("\(Int(seconds / 60)) min")
    }

    private func edit<Value>(_ keyPath: WritableKeyPath<Endpoint, Value>) -> Binding<Value> {
        Binding(
            get: { endpoint[keyPath: keyPath] },
            set: { value in
                var changed = endpoint
                changed[keyPath: keyPath] = value
                onChange(changed)
            }
        )
    }

    private func commitURL() {
        guard let url = URL(string: urlText), url.scheme != nil, url != endpoint.url else {
            urlText = endpoint.url.absoluteString
            return
        }
        var changed = endpoint
        changed.url = url
        onChange(changed)
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
            Section {
                Slider(value: dock.iconSize, in: 32 ... 96) { Text(loc("Icon size")) }
                Toggle(loc("Magnification"), isOn: dock.magnifies)
                Slider(value: dock.magnifiedSize, in: 48 ... 128) { Text(loc("Magnified size")) }
                Toggle(loc("Show Trash"), isOn: dock.showsTrash)
                Toggle(loc("Show Recent Apps"), isOn: dock.showsRecents)
                Toggle(loc("Show Running Indicators"), isOn: dock.showsRunningIndicators)
            } header: {
                Text(loc("Size"))
            } footer: {
                Text(loc("Widgets in the Dock are as big as app icons: this size sets both."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text(
                    loc("Drag one app onto another in the Dock to make a folder, or drop an app on a folder to add it.")
                )
                Text(
                    loc(
                        "Right-click an empty part of the Dock → New Folder, or an app → Options → Add to Folder."
                    )
                )
            } header: {
                Text(loc("Folders"))
            }
            .font(.callout)
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
            DockScheduleSection(store: store)
            DockSystemSection(store: store)
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isExplaining) {
            DockFirstRunView(
                presets: presets,
                proceed: {
                    isExplaining = false
                    enable()
                },
                applyPreset: { preset in
                    store.update { DockPresets.apply(preset, current: nil, to: &$0.dock) }
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
            // Rows are dragged by hand: `onMove` does nothing inside a `Form`. The arrows do the same by click.
            ForEach(widgets) { module in
                HStack {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    Text(module.title)
                    Spacer()
                    Text(module.dockClickTitle).font(.caption).foregroundStyle(.secondary)
                    Button { setWidgets(DockLayout.moving(module, by: -1, in: widgets)) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(module == widgets.first)
                    .help(loc("Move Up"))
                    Button { setWidgets(DockLayout.moving(module, by: 1, in: widgets)) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(module == widgets.last)
                    .help(loc("Move Down"))
                    Button(loc("Remove")) { setWidgets(widgets.filter { $0 != module }) }
                }
                .contentShape(.rect)
                .draggable(module.rawValue)
                .dropDestination(for: String.self) { dropped, _ in
                    guard let raw = dropped.first, let dragged = ModuleID(rawValue: raw), widgets.contains(dragged)
                    else { return false }
                    setWidgets(DockLayout.moving(dragged, onto: module, in: widgets))
                    return true
                }
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
            if let active = presets.first(where: { $0.id == store.settings.dock.activePreset }) {
                Button(loc("Turn Off Presets")) {
                    store.update { DockPresets.turnOff(current: active, in: &$0.dock) }
                }
            }
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

    var showsRecents: Binding<Bool> {
        Binding(
            get: { store.settings.dock.showsRecents },
            set: { value in store.update { $0.dock.showsRecents = value } }
        )
    }

    var showsRunningIndicators: Binding<Bool> {
        Binding(
            get: { store.settings.dock.showsRunningIndicators },
            set: { value in store.update { $0.dock.showsRunningIndicators = value } }
        )
    }

    var showsTrash: Binding<Bool> {
        Binding(get: { store.settings.dock.showsTrash }, set: { value in store.update { $0.dock.showsTrash = value } })
    }
}
