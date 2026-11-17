import AppKit
import GlassWorkCore
import GlassWorkUI
import ServiceManagement
import SwiftUI
import UserNotifications

/// The Settings window and the first-launch welcome.
@MainActor
final class SettingsWindowController {
    private unowned let model: AppModel
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?
    private var welcome: NSWindow?
    private let navigation = SettingsNavigation()

    init(model: AppModel) {
        self.model = model
    }

    func showFans() {
        navigation.selection = .fans
        navigation.fanCurveRequests += 1
        show(module: nil)
    }

    func showWidgets() {
        navigation.selection = .widgets
        show(module: nil)
    }

    func show(module: ModuleID?) {
        navigation.selection = module.map(SettingsPage.module) ?? navigation.selection
        if window == nil {
            let view = SettingsRoot(
                store: model.store,
                monitor: model.monitor,
                fans: model.fans,
                shortcuts: model.shortcuts,
                navigation: navigation
            )
            let created = NSWindow(contentViewController: NSHostingController(rootView: view))
            created.title = loc("GlassWork Settings")
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            created.toolbarStyle = .unified
            created.contentMinSize = CGSize(width: 760, height: 540)
            created.setContentSize(CGSize(width: 900, height: 640))
            created.setFrameAutosaveName("GlassWorkSettings")
            created.isReleasedWhenClosed = false
            window = created
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: created,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.model.settingsChanged(isOpen: false)
                    self?.releaseWindow()
                }
            }
        }
        model.settingsChanged(isOpen: true)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// A closed Settings window keeps its whole SwiftUI tree; the next open builds a fresh one.
    private func releaseWindow() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, let window, !window.isVisible else { return }
            window.contentViewController = nil
            self.window = nil
        }
    }

    func showWelcome() {
        let view = WelcomeView(
            store: model.store,
            openSettings: { [weak self] in self?.show(module: nil) },
            addWidgets: { [weak self] in self?.showWidgets() },
            finish: { [weak self] in
                self?.welcome?.close()
                self?.welcome = nil
            }
        )
        let created = NSWindow(contentViewController: NSHostingController(rootView: view))
        created.title = loc("Welcome to GlassWork")
        created.styleMask = [.titled, .closable, .fullSizeContentView]
        created.titlebarAppearsTransparent = true
        created.center()
        created.isReleasedWhenClosed = false
        welcome = created
        NSApp.activate()
        created.makeKeyAndOrderFront(nil)
    }
}

typealias SettingsPage = SettingsDestination

@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPage = .menuBar
    /// Counts "Edit curves…" clicks. Each one opens the Curves tab, even if it was left.
    var fanCurveRequests = 0
    /// The search result last opened: its row stands out until the search is cleared.
    var openedResult: String?
}

struct SettingsRoot: View {
    let store: SettingsStore
    let monitor: SystemMonitor
    let fans: FanControlModel
    let shortcuts: ShortcutCenter
    @Bindable var navigation: SettingsNavigation
    @State private var query = ""
    @State private var toast: SettingsToast?
    /// Whether the module list under Menu Bar is open. Remembered between launches.
    @AppStorage("settings.menuBarModulesExpanded") private var modulesExpanded = true

    private var modules: [ModuleSettings] {
        store.settings.modules.filter(\.id.isAvailable)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .searchable(text: $query, placement: .sidebar)
                .onSubmit(of: .search) {
                    if let first = SettingsIndex.search(query).first {
                        open(first.result)
                    }
                }
                .onChange(of: query) { _, new in
                    if new.isEmpty {
                        navigation.openedResult = nil
                    }
                }
                .navigationSplitViewColumnWidth(220)
        } detail: {
            detail
                .environment(\.settingsHighlight, navigation.openedResult)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { undoButtons }
                .overlay(alignment: .bottom) { toastView }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            SettingsToastView(toast) {
                if toast.isUndo {
                    undo()
                } else {
                    redo()
                }
            }
            .padding(.bottom, 16)
            .transition(.opacity)
            .id(toast.id)
            .task(id: toast.id) {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation { self.toast = nil }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if query.isEmpty {
            List(selection: $navigation.selection) {
                row(.general, loc("General"), "gearshape", .gray)
                menuBarRow
                ForEach(modulesExpanded ? modules : []) { setting in
                    Label {
                        Text(setting.id.title)
                    } icon: {
                        ModuleIcon(setting.id, size: 18)
                    }
                    .padding(.leading, 14)
                    .tag(SettingsPage.module(setting.id))
                }
                row(.widgets, loc("Widgets"), "square.grid.2x2", .purple)
                row(.dock, loc("Dock"), "dock.rectangle", .teal)
                row(.fans, loc("Fans"), "fan", .cyan)
                row(.windowTiles, loc("Window Tiles"), "rectangle.split.2x1", .teal)
                row(.shortcuts, loc("Shortcuts"), "keyboard", .gray)
                row(.permissions, loc("Permissions"), "checkmark.shield", .green)
                row(.about, loc("About"), "info.circle", .gray)
            }
        } else {
            SettingsSearchResults(query: query, opened: navigation.openedResult, open: open)
        }
    }

    /// Menu Bar with a chevron that opens and closes the module list under it.
    private var menuBarRow: some View {
        HStack(spacing: 0) {
            row(.menuBar, loc("Menu Bar"), "menubar.rectangle", .blue)
            Spacer(minLength: 4)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { modulesExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(modulesExpanded ? 90 : 0))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(modulesExpanded ? loc("Hide modules") : loc("Show modules"))
        }
        .tag(SettingsPage.menuBar)
    }

    private func open(_ result: SettingsResult) {
        navigation.selection = result.destination
        navigation.openedResult = result.id
        if case .module = result.destination {
            modulesExpanded = true
        }
    }

    /// Changes apply instantly; ⌘Z takes back the last one and ⇧⌘Z brings it back.
    private var undoButtons: some View {
        ZStack {
            Button("") { undo() }
                .keyboardShortcut("z")
                .disabled(store.undoStack.isEmpty)
            Button("") { redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(store.redoStack.isEmpty)
        }
        .opacity(0)
    }

    private func undo() {
        guard let change = store.undo() else { return }
        show(SettingsToast(message: loc("Undone: \(change.title)"), actionTitle: loc("Redo"), isUndo: false))
    }

    private func redo() {
        guard let change = store.redo() else { return }
        show(SettingsToast(message: loc("Redone: \(change.title)"), actionTitle: loc("Undo"), isUndo: true))
    }

    private func show(_ new: SettingsToast) {
        withAnimation { toast = new }
    }

    private func row(_ page: SettingsPage, _ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(color.gradient, in: .rect(cornerRadius: 5))
        }
        .tag(page)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .general: GeneralPane(store: store)
        case .menuBar: ModulesPane(store: store)
        case let .module(id): ModulePane(module: id, store: store, monitor: monitor)
        case .shortcuts:
            ShortcutsPane(store: store, refused: shortcuts.refused) { shortcuts.setRecording($0) }
        case .widgets: WidgetsPane(store: store, personal: monitor.personal, activity: monitor.activity)
        case .dock: DockPane(store: store)
        case .fans:
            FansSettingsPane(
                control: fans,
                sample: monitor.sensors,
                isOnAC: monitor.battery?.isOnAC ?? true,
                showsCurves: navigation.fanCurveRequests > 0
            )
            .id(navigation.fanCurveRequests)
        case .windowTiles: WindowTilesPage(store: store, shortcuts: shortcuts)
        case .permissions: PermissionsPane(store: store, monitor: monitor)
        case .about: AboutPane()
        }
    }
}

struct ModulesPane: View {
    let store: SettingsStore

    /// A `List`, because rows only drag there: `onMove` does nothing inside a `Form`.
    var body: some View {
        List {
            Text(loc("In menu bar, Hub only or Off. Click a module in the sidebar for its options; drag to reorder."))
                .font(.caption)
                .foregroundStyle(.secondary)
            ModuleOrderSections(store: store)
            Section {
                HStack {
                    Button(loc("All to Hub")) { setAll(.hubOnly) }
                    Button(loc("All to menu bar")) { setAll(.menuBar) }
                    Button(loc("All off")) { setAll(.off) }
                    Spacer()
                    Button(loc("Reset order")) { store.update { $0.resetModuleOrder() } }
                    Button(loc("Restore defaults")) { store.update { $0.modules = AppSettings.defaultModules } }
                }
            }
            HubOptionRows(store: store)
            Section(loc("Hiding")) {
                Toggle(loc("Hide items behind a separator"), isOn: hidingEnabled)
                Stepper(value: autoHide, in: 3 ... 60) {
                    Text(loc("Hide again after \(store.settings.hiding.autoHideSeconds) s"))
                }
                LabeledContent(loc("To remove a macOS item for good, turn it off in System Settings.")) {
                    Button(loc("Menu Bar Settings…"), action: Self.openMenuBarSettings)
                }
                Text(loc("""
                Everything left of ‹ hides, macOS items such as Wi-Fi and Battery too. \
                Hold ⌘ and drag an item across ‹ to choose. The clock and Control Center always stay.
                """))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
    }

    /// Only opens the page: which macOS items are shown stays the user's change to make there.
    private static func openMenuBarSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private var hidingEnabled: Binding<Bool> {
        Binding(
            get: { store.settings.hiding.isEnabled },
            set: { value in store.update { $0.hiding.isEnabled = value } }
        )
    }

    private var autoHide: Binding<Int> {
        Binding(
            get: { store.settings.hiding.autoHideSeconds },
            set: { value in store.update { $0.hiding.autoHideSeconds = value } }
        )
    }

    private func setAll(_ mode: ModuleMode) {
        store.update { settings in
            for index in settings.modules.indices where settings.modules[index].id.isAvailable {
                settings.modules[index].mode = mode
            }
        }
    }
}

struct ModulePane: View {
    let module: ModuleID
    let store: SettingsStore
    let monitor: SystemMonitor
    /// Read once: a Mac does not gain or lose its battery while Settings is open.
    private let hasBattery = HardwareAvailability.current.hasBattery

    private var lacksBattery: Bool {
        module == .battery && !hasBattery
    }

    private var style: Binding<DisplayStyle> {
        Binding(
            get: { store.settings.module(module)?.style ?? .figure },
            set: { value in store.update { $0.update(module) { $0.style = value } } }
        )
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ModuleIcon(module, size: 32)
                    Text(module.title).font(.title3.weight(.semibold))
                    Spacer()
                    ModePicker(module: module, store: store).frame(width: 150)
                }
            }
            Section(loc("Display style")) {
                Picker(loc("Style"), selection: style) {
                    ForEach(DisplayStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent(loc("Preview")) {
                    MenuBarItemView(
                        module: module,
                        style: style.wrappedValue,
                        numbers: store.settings.numberStyle,
                        options: options,
                        monitor: monitor
                    )
                }
            }
            if lacksBattery {
                Section {
                    Label(loc("This Mac has no battery"), systemImage: "battery.0percent")
                        .foregroundStyle(.secondary)
                }
            }
            Group {
                ModuleOptions(module: module, store: store, agenda: monitor.agenda)
                ModuleOptionRows(module: module, store: store)
            }
            .disabled(lacksBattery)
            if module == .sensors {
                SensorsMenuBarSection(selection: sensor, sample: monitor.sensors)
                SensorGroupsSection(store: store)
            }
            if module == .fans {
                FansMenuBarSection(showsEachFan: showsEachFan)
            }
        }
        .formStyle(.grouped)
    }

    private var options: [String: String] {
        store.settings.module(module)?.options ?? [:]
    }

    private var sensor: Binding<SensorChoice> {
        Binding(
            get: { .shown(by: options) },
            set: { value in store.update { $0.update(module) { $0.options[ModuleOption.sensor] = value.rawValue } } }
        )
    }

    private var showsEachFan: Binding<Bool> {
        Binding(
            get: { options[ModuleOption.fanFigure] == ModuleOption.eachFan },
            set: { value in
                let figure = value ? ModuleOption.eachFan : "average"
                store.update { $0.update(module) { $0.options[ModuleOption.fanFigure] = figure } }
            }
        )
    }
}

struct GeneralPane: View {
    let store: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle(loc("Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { store.settings.island.isEnabled },
                    set: { value in store.update { $0.island.isEnabled = value } }
                )) {
                    VStack(alignment: .leading) {
                        Text(loc("Island"))
                        Text(loc("Shows what is happening around the camera notch"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(loc("Open the island on hover"), isOn: Binding(
                    get: { store.settings.island.expandsOnHover },
                    set: { value in store.update { $0.island.expandsOnHover = value } }
                ))
            }
            Section(loc("Numbers")) {
                Picker(loc("Menu bar figures"), selection: Binding(
                    get: { store.settings.numberStyle },
                    set: { value in store.update { $0.numberStyle = value } }
                )) {
                    Text(loc("Compact")).tag(NumberStyle.compact)
                    Text(loc("Precise")).tag(NumberStyle.precise)
                }
            }
            Section(loc("Notifications")) {
                Toggle(loc("Notify about low battery and high temperature"), isOn: alertsEnabled)
            }
            GeneralRegionalSection(store: store)
            GeneralUpdatesSection()
            DiagnosticLogSection(
                isOn: keepsLog,
                path: (DiagnosticLog.defaultURL.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath,
                size: DiagnosticLog.size(of: DiagnosticLog.defaultURL),
                reveal: { NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.defaultURL]) },
                send: sendLog
            )
            Section(loc("Settings file")) {
                LabeledContent("settings.json") {
                    Button(loc("Reveal in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([SettingsFile.defaultURL])
                    }
                }
                HStack {
                    Button(loc("Export…"), action: exportSettings)
                    Button(loc("Import…"), action: importSettings)
                    Spacer()
                    Button(loc("Reset all…"), role: .destructive, action: confirmReset)
                }
                ForEach(store.backups.list()) { backup in
                    LabeledContent(backup.date.formatted(date: .abbreviated, time: .shortened)) {
                        Button(loc("Restore")) {
                            if let settings = store.backups.load(backup) {
                                store.replace(with: settings)
                            }
                        }
                    }
                }
                if let error = store.lastError {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralPane {
    /// Asks first. The backup is on by default, so a reset can always be walked back from the list below.
    func confirmReset() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = loc("Reset all settings?")
        alert.informativeText = loc("Everything returns to its defaults. ⌘Z takes it back.")
        let backup = NSButton(checkboxWithTitle: loc("Save a backup first"), target: nil, action: nil)
        backup.state = .on
        backup.sizeToFit()
        alert.accessoryView = backup
        alert.addButton(withTitle: loc("Reset")).hasDestructiveAction = true
        alert.addButton(withTitle: loc("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.replace(with: AppSettings(), backup: backup.state == .on)
    }

    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GlassWork Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SettingsFile(url: url).save(store.settings)
    }

    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let settings = try? SettingsFile(url: url).load()
        else { return }
        store.replace(with: settings)
    }

    var keepsLog: Binding<Bool> {
        Binding(
            get: { store.settings.keepsDiagnosticLog },
            set: { value in store.update { $0.keepsDiagnosticLog = value } }
        )
    }

    /// Opens a draft and stops there: sending it, and to whom, stays with the user.
    func sendLog() {
        guard let service = NSSharingService(named: .composeEmail) else { return }
        service.subject = loc("GlassWork diagnostic log")
        service.perform(withItems: [DiagnosticLog.defaultURL])
    }

    /// macOS asks for permission the first time this is turned on.
    var alertsEnabled: Binding<Bool> {
        Binding(
            get: { store.settings.alerts.isEnabled },
            set: { value in
                store.update { $0.alerts.isEnabled = value }
                if value {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
            }
        )
    }
}
