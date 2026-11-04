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

    func show(module: ModuleID?) {
        navigation.selection = module.map(SettingsPage.module) ?? navigation.selection
        if window == nil {
            let view = SettingsRoot(
                store: model.store,
                monitor: model.monitor,
                fans: model.fans,
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
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: created,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.settingsChanged(isOpen: false) }
            }
        }
        model.settingsChanged(isOpen: true)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func showWelcome() {
        let view = WelcomeView(store: model.store) { [weak self] in
            self?.welcome?.close()
            self?.welcome = nil
        }
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

enum SettingsPage: Hashable {
    case general, menuBar, widgets, dock, fans, shortcuts, permissions, about
    case module(ModuleID)
}

@MainActor
@Observable
final class SettingsNavigation {
    var selection: SettingsPage = .menuBar
    /// Counts "Edit curves…" clicks. Each one opens the Curves tab, even if it was left.
    var fanCurveRequests = 0
}

struct SettingsRoot: View {
    let store: SettingsStore
    let monitor: SystemMonitor
    let fans: FanControlModel
    @Bindable var navigation: SettingsNavigation
    @State private var query = ""

    private var modules: [ModuleSettings] {
        store.settings.modules.filter { setting in
            setting.id.isAvailable && (query.isEmpty || setting.id.title.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                row(.general, loc("General"), "gearshape", .gray)
                row(.menuBar, loc("Menu Bar"), "menubar.rectangle", .blue)
                ForEach(modules) { setting in
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
                row(.shortcuts, loc("Shortcuts"), "keyboard", .gray)
                row(.permissions, loc("Permissions"), "checkmark.shield", .green)
                row(.about, loc("About"), "info.circle", .gray)
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(220)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background { undoButton }
        }
    }

    /// Changes apply instantly; ⌘Z takes back the last one.
    private var undoButton: some View {
        Button("") { store.undo() }
            .keyboardShortcut("z")
            .disabled(store.undoStack.isEmpty)
            .opacity(0)
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
        case .shortcuts: ShortcutsPane()
        case .widgets: WidgetsPane(store: store)
        case .dock: DockPane(store: store)
        case .fans:
            FansSettingsPane(
                control: fans,
                sample: monitor.sensors,
                isOnAC: monitor.battery?.isOnAC ?? true,
                showsCurves: navigation.fanCurveRequests > 0
            )
            .id(navigation.fanCurveRequests)
        case .about: AboutPane()
        default: ContentUnavailableView(loc("Coming soon"), systemImage: "hammer")
        }
    }
}

struct ModulesPane: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                ForEach(store.settings.modules.filter(\.id.isAvailable)) { setting in
                    HStack(spacing: 10) {
                        ModuleIcon(setting.id, size: 26)
                        Text(setting.id.title)
                        Spacer()
                        ModePicker(module: setting.id, store: store).frame(width: 150)
                    }
                }
            } header: {
                Text(loc("Modules"))
            } footer: {
                Text(loc("In menu bar, Hub only or Off. Click a module in the sidebar for its options."))
            }
            Section {
                HStack {
                    Button(loc("All to Hub")) { setAll(.hubOnly) }
                    Button(loc("All to menu bar")) { setAll(.menuBar) }
                    Spacer()
                    Button(loc("Restore defaults")) { store.update { $0.modules = AppSettings.defaultModules } }
                }
            }
            Section {
                Toggle(loc("Hide items behind a separator"), isOn: hidingEnabled)
                Stepper(value: autoHide, in: 3 ... 60) {
                    Text(loc("Hide again after \(store.settings.hiding.autoHideSeconds) s"))
                }
                LabeledContent(loc("To remove a macOS item for good, turn it off in System Settings.")) {
                    Button(loc("Menu Bar Settings…"), action: Self.openMenuBarSettings)
                }
            } header: {
                Text(loc("Hiding"))
            } footer: {
                Text(loc("""
                Everything left of ‹ hides, macOS items such as Wi-Fi and Battery too. \
                Hold ⌘ and drag an item across ‹ to choose. The clock and Control Center always stay.
                """))
            }
        }
        .formStyle(.grouped)
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

struct ModePicker: View {
    let module: ModuleID
    let store: SettingsStore

    var body: some View {
        Picker("", selection: Binding(
            get: { store.settings.module(module)?.mode ?? .off },
            set: { value in store.update { $0.update(module) { $0.mode = value } } }
        )) {
            Text(loc("In menu bar")).tag(ModuleMode.menuBar)
            Text(loc("Hub only")).tag(ModuleMode.hubOnly)
            Text(loc("Off")).tag(ModuleMode.off)
        }
        .labelsHidden()
    }
}

struct ModulePane: View {
    let module: ModuleID
    let store: SettingsStore
    let monitor: SystemMonitor

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
                    Text(loc("Symbol")).tag(DisplayStyle.symbol)
                    Text(loc("Figure")).tag(DisplayStyle.figure)
                    Text(loc("Graph")).tag(DisplayStyle.graph)
                    Text(loc("Graph and figure")).tag(DisplayStyle.graphAndFigure)
                    Text(loc("Labelled")).tag(DisplayStyle.labelled)
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
            ModuleOptions(module: module, store: store)
            if module == .sensors {
                SensorsMenuBarSection(selection: sensor, sample: monitor.sensors)
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
                    Button(loc("Reset all…"), role: .destructive) { store.replace(with: AppSettings()) }
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

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("GlassWork").font(.largeTitle.weight(.semibold))
            Text(loc("Version \(version)")).foregroundStyle(.secondary)
            Link(
                "github.com/EvgenyBaulin/GlassWork",
                destination: URL(string: "https://github.com/EvgenyBaulin/GlassWork")!
            )
            Text(loc("MIT License")).foregroundStyle(.secondary)
        }
    }
}

/// Four steps with Skip: welcome, what to enable, permissions, done.
struct WelcomeView: View {
    let store: SettingsStore
    let finish: () -> Void
    @State private var step = 0
    @State private var launchAtLogin = true

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            content
            Spacer()
            HStack {
                Button(loc("Skip")) { complete() }.buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(step == 3 ? loc("Done") : loc("Continue")) { advance() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520, height: 380)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            Text(loc("Welcome to GlassWork")).font(.largeTitle.weight(.semibold))
            Text(loc("Live figures in your menu bar, with everything else one click away in the Hub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case 1:
            Text(loc("What to enable")).font(.title.weight(.semibold))
            Text(loc("Overview, CPU and Memory start in the menu bar. Everything else waits in the Hub."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        case 2:
            Text(loc("Permissions")).font(.title.weight(.semibold))
            Text(loc("Nothing is needed now. Each module asks for access only when you turn it on."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        default:
            Text(loc("All set")).font(.title.weight(.semibold))
            Toggle(loc("Launch at login"), isOn: $launchAtLogin).toggleStyle(.checkbox)
        }
    }

    private func advance() {
        if step == 3 {
            complete()
        } else {
            step += 1
        }
    }

    private func complete() {
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        }
        store.update { $0.welcomeCompleted = true }
        finish()
    }
}
