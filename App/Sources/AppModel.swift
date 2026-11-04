import AppKit
import GlassWorkCore
import GlassWorkUI
import Observation
import SwiftUI
import UserNotifications
import WidgetKit

/// Owns the app's long-lived objects and keeps them in step with settings.
@MainActor
final class AppModel {
    let store = SettingsStore()
    private let diagnostics = DiagnosticsReporter()
    let monitor = SystemMonitor(
        nowPlaying: NowPlayingBridge.makeStore(),
        personal: PersonalWidgetStore(library: SystemPhotoLibrary(), contacts: SystemBirthdays())
    )
    private let fanSensors = FanSensorSource()
    private(set) lazy var fans = makeFans()
    private lazy var panels = PanelController(model: self)
    private lazy var statusBar = StatusBarController(model: self)
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private lazy var mainWindow = MainWindowController(model: self)
    private lazy var runningApps = RunningAppsObserver(store: monitor.apps)
    private lazy var quickQuit = QuickQuitController(model: self)
    private let quitter = QuitService(system: WorkspaceQuitSystem())
    private lazy var desktopWidgets = DesktopWidgetController(model: self)
    private lazy var dock = DockController(model: self)
    private(set) lazy var clipboard = ClipboardController(model: self)
    private lazy var textCapture = TextCaptureController(model: self)
    private(set) lazy var windowTiles = WindowTilesController(model: self)
    private lazy var location = LocationProvider(store: monitor.weather)
    private lazy var nowPlaying = NowPlayingBridge(
        store: monitor.nowPlaying,
        refreshSeconds: store.settings.widgets.refreshSeconds
    )
    let shortcuts = ShortcutCenter()
    private var hasOpenPanel = false
    private var isSettingsOpen = false
    private var visibleSection: MainSection?
    private var isQuickQuitOpen = false
    private var timer: Timer?
    private var thresholds = ThresholdTracker()
    /// Widgets in the system's desktop layer, as WidgetKit last reported them.
    private var systemWidgetKinds: Set<WidgetKind> = []

    init() {
        observeSleep()
        observeFrontApp()
        // First, so nothing takes the default keys of a shortcut the user changed.
        shortcuts.apply(store.settings.shortcuts)
        shortcuts.onRefused = { [diagnostics] in diagnostics.record(.shortcutRefused(action: $0.id)) }
        monitor.activity.onGitHubFailed = { [diagnostics] in diagnostics.record(.gitHubFailed(status: $0)) }
        shortcuts.bind(.hub) { [weak self] in self?.toggleHub() }
        shortcuts.setActive(.hub, true)
        _ = textCapture
        Task { await monitor.clipboard.load() }
        Task { await monitor.apps.load() }
        _ = runningApps
        _ = quickQuit
        applySettings()
        checkSystemWidgets()
        fans.onFailsafe = { celsius in
            FanNotifications.failsafe(
                celsius: celsius,
                title: loc("CPU \(Format.temperature(celsius)) — switched to Max"),
                body: loc("Average CPU went above 95 °C. Max stays on until you pick a mode.")
            )
        }
        fans.applyLaunchMode()
        monitor.onUpdate = { [weak self] in
            self?.statusBar.refreshItems()
            self?.checkAlerts()
        }
        monitor.start()
        observeWidgetCommands()
        writeHeartbeat()
        let refresh = TimeInterval(store.settings.widgets.refreshSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: refresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeHeartbeat() }
        }
        if !store.settings.welcomeCompleted {
            settingsWindow.showWelcome()
        }
    }

    private func makeFans() -> FanControlModel {
        let sensors = fanSensors
        return FanControlModel(
            store: store,
            installer: FanHelperInstaller(),
            readSensors: { await sensors.sample() },
            // A desktop Mac has no battery, so no reading means mains power.
            isOnAC: { [weak self] in self?.monitor.battery?.isOnAC ?? true }
        )
    }

    var actions: PanelActions {
        PanelActions(
            openSettings: { [weak self] module in self?.showSettings(module: module) },
            detach: { [weak self] module in self?.panels.detach(module) },
            openApp: { bundleID in
                guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            },
            openURL: { NSWorkspace.shared.open($0) },
            quit: { [weak self] in self?.quit($0, force: $1) },
            showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: $0)]) },
            updateSettings: { [weak self] change in self?.store.update(change) },
            useClipboardEntry: { [weak self] entry, plain in self?.clipboard.use(entry, plainText: plain) },
            isPasteAllowed: { Accessibility.isTrusted },
            openFanCurves: { [weak self] in self?.showFanCurves() },
            moduleOptions: { [weak self] in self?.store.settings.module($0)?.options ?? [:] }
        )
    }

    /// Gives the system Dock back when the app quits.
    func prepareToQuit() {
        dock.restoreSystemDock()
        monitor.apps.saveNow()
        monitor.nowPlaying.stop()
        nowPlaying.prepareToQuit()
    }

    func showSettings(module: ModuleID? = nil) {
        panels.closeTransient()
        settingsWindow.show(module: module)
    }

    func showMainWindow() {
        panels.closeTransient()
        mainWindow.show()
    }

    func showMainWindow(_ section: MainSection) {
        panels.closeTransient()
        mainWindow.show(section)
    }

    /// The welcome comes first on a new Mac.
    func showMainWindowAtLaunch() {
        if store.settings.welcomeCompleted {
            showMainWindow()
        }
    }

    func showFanCurves() {
        panels.closeTransient()
        settingsWindow.showFans()
    }

    func togglePanel(_ module: ModuleID, from button: NSStatusBarButton) {
        panels.toggle(module, from: button)
    }

    /// Keep Awake, Stopwatch and Appearance act on the click itself.
    func performClickAction(_ module: ModuleID) {
        panels.closeTransient()
        let store = monitor.everyday
        switch module {
        case .keepAwake: store.toggleKeepAwake()
        case .stopwatch: store.update { $0.stopwatch.toggle(at: Date()) }
        case .appearance: Appearance.toggle()
        default: break
        }
    }

    func showPanel(_ module: ModuleID, beside frame: CGRect) {
        panels.show(module, beside: frame)
    }

    /// For a click on a system widget, whose frame the app never learns.
    func showPanelAtPointer(_ module: ModuleID) {
        showPanel(module, beside: CGRect(origin: NSEvent.mouseLocation, size: .zero))
    }

    func toggleHub() {
        statusBar.revealHidden()
        panels.toggleHub(from: statusBar.hubButton)
    }

    func panelsChanged(hasOpenPanel: Bool) {
        self.hasOpenPanel = hasOpenPanel
        updateDemand()
        dock.cardsChanged()
        if hasOpenPanel {
            monitor.refresh()
            monitor.apps.refresh()
        }
    }

    /// The fan and sensor panes show live readings, which no panel may be asking for.
    func settingsChanged(isOpen: Bool) {
        isSettingsOpen = isOpen
        updateDemand()
        if isOpen {
            monitor.refresh()
        }
    }

    /// What the main window has on screen, or nil while it is closed or covered.
    func mainWindowChanged(visibleSection: MainSection?) {
        self.visibleSection = visibleSection
        updateDemand()
        if visibleSection == .apps || visibleSection == .overview {
            monitor.refresh(includingSlow: true)
            monitor.apps.refresh()
        }
    }

    func quickQuitChanged(isOpen: Bool) {
        isQuickQuitOpen = isOpen
        updateDemand()
        if isOpen {
            monitor.apps.refresh()
        }
    }

    /// Every Quit in the app comes through here. The service decides what may be quit, not the buttons.
    func quit(_ target: QuitTarget, force: Bool) {
        if quitter.quit(target, force: force) == .sent {
            monitor.refresh()
        }
    }

    /// Runs now and again whenever settings change.
    private func applySettings() {
        withObservationTracking {
            _ = store.settings
            _ = store.lastError
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySettings() }
        }
        shortcuts.apply(store.settings.shortcuts)
        applyInfoModules()
        statusBar.apply(store.settings)
        monitor.developer.options = DeveloperOptions(settings: store.settings)
        desktopWidgets.apply(store.settings.widgets)
        dock.apply(store.settings.dock)
        windowTiles.apply(store.settings.windowTiles)
        monitor.temperatureSource = .shown(by: store.settings.module(.sensors)?.options ?? [:])
        applyPolling()
        diagnostics.apply(keepsLog: store.settings.keepsDiagnosticLog, hasSettingsProblem: store.lastError != nil)
        updateDemand()
    }

    /// Goes first: the width of a menu bar item depends on these settings.
    private func applyInfoModules() {
        let settings = store.settings
        monitor.weather.apply(settings.weather)
        monitor.rates.apply(settings.rates)
        monitor.clipboard.apply(settings.clipboard)
        location.apply(isOn: settings.weather.useCurrentLocation && settings.module(.weather)?.mode != .off)
        clipboard.apply(settings.clipboard, isEnabled: settings.module(.clipboard)?.mode != .off)
    }

    /// Network modules ask only while they are in the bar or a panel can show them.
    private func isWanted(_ module: ModuleID) -> Bool {
        let mode = store.settings.module(module)?.mode
        return mode == .menuBar || (hasOpenPanel && mode != .off) || store.settings.dock.shownWidgets.contains(module)
    }

    private func updateDemand() {
        // Live windows and charts sample on every tick; other system widgets read once a minute.
        let placed = placedWidgetKinds
        var demand = MonitorDemand(widgets: desktopWidgetKinds.union(systemWidgetKinds.filter(\.keepsHistory)))
            .adding(visibleSection?.monitorDemand ?? MonitorDemand())
        // A widget in the Dock shows a live figure, just as a menu bar item does.
        let docked = store.settings.dock.shownWidgets
        let modes = store.settings.modules.filter { $0.mode == .menuBar }.map(\.id) + docked
        let everything = hasOpenPanel
        demand.liveApps = demand.liveApps || everything || isQuickQuitOpen
        demand.cpu = demand.cpu || everything || modes.contains(.cpu) || modes.contains(.overview)
        demand.memory = demand.memory || everything || modes.contains(.memory) || modes.contains(.overview)
        demand.network = demand.network || everything || modes.contains(.network)
        let overviewShowsDisk = modes.contains(.overview)
            && store.settings.module(.overview)?.options.flag(ItemOption.showsDisk, default: false) == true
        demand.disk = demand.disk || everything || modes.contains(.disk) || modes.contains(.eject) || overviewShowsDisk
        demand.battery = true
        demand.gpu = demand.gpu || everything || modes.contains(.gpu)
        demand.sensors = demand.sensors || everything || isSettingsOpen || modes.contains(.sensors)
            || modes.contains(.fans) || store.settings.alerts.isEnabled
        demand.sensorDetail = everything || isSettingsOpen ? .live : demand.sensorDetail
        demand.processes = everything
        demand.developer = store.settings.developerDemand(panelOpen: everything)
            .union(placed.compactMap(\.developerModule))
            .union(docked.intersection(ModuleID.developerCollected))
        // Only on request: the module is in the Hub by default, and the read may raise a Bluetooth prompt.
        demand.devices = placed.contains(.devices) || modes.contains(.deviceBatteries)
        demand.timeMachine = placed.contains(.timeMachine)
        demand.nowPlaying = wantsNowPlaying
        monitor.nowPlaying.wantsLyrics = wantsLyrics
        monitor.demand = demand
        monitor.weather.isActive = isWanted(.weather) || placed.contains(.weather)
        monitor.rates.isActive = isWanted(.rates) || placed.contains(.rates)
    }

    private var desktopWidgetKinds: Set<WidgetKind> {
        Set(store.settings.widgets.placements.map(\.kind))
    }

    private var placedWidgetKinds: Set<WidgetKind> {
        desktopWidgetKinds.union(systemWidgetKinds)
    }

    func closePanels() {
        panels.closeTransient()
    }

    func closeQuickPaste() {
        clipboard.closeQuickPaste()
    }

    func closeQuickQuit() {
        quickQuit.close()
    }

    func copyToPasteboard(_ text: String) {
        clipboard.copy(text)
    }

    func isStatusItem(_ window: NSWindow) -> Bool {
        statusBar.owns(window)
    }

    private func writeHeartbeat() {
        checkSystemWidgets()
        Task {
            let hasNewWidgets = await refreshSystemWidgetKinds()
            let kinds = placedWidgetKinds
            if kinds.contains(.endpoints) {
                await monitor.activity.check(store.settings.widgets.endpoints)
            }
            if !kinds.isDisjoint(with: WidgetKind.githubKinds) {
                await monitor.activity.refreshGitHub(
                    includesDigest: kinds.contains(.github),
                    includesRuns: kinds.contains(.githubActions)
                )
            }
            await monitor.personal.refresh(store.settings.personalWidgets, for: kinds)
            if store.settings.widgets.tracksScreenTime, !kinds.isDisjoint(with: WidgetKind.screenTimeKinds) {
                monitor.activity.flushScreenTime()
            }
            fans.refreshHelperState()
            await publishSystemWidgets()
            // A widget just added waits for its first reads, so it gets a second look instead of a full minute.
            if hasNewWidgets {
                monitor.refresh()
                try? await Task.sleep(for: .seconds(5))
                await publishSystemWidgets()
            }
        }
    }

    private func publishSystemWidgets() async {
        await monitor.readForWidgets(systemWidgetKinds)
        guard writeWidgetSnapshot(), !systemWidgetKinds.isEmpty else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// True when widgets were added or removed. A failed call keeps the last answer: forgetting placed widgets
    /// would blank them.
    private func refreshSystemWidgetKinds() async -> Bool {
        guard let widgets = try? await WidgetCenter.shared.currentConfigurations() else { return false }
        let kinds = Set(widgets.compactMap { WidgetKind(rawValue: $0.kind) })
        guard kinds != systemWidgetKinds else { return false }
        systemWidgetKinds = kinds
        updateDemand()
        return true
    }

    /// The one place widget data comes together, for system widgets and GlassWork's own windows alike.
    func makeWidgetSnapshot() -> WidgetSnapshot {
        let kinds = placedWidgetKinds
        var snapshot = monitor.widgetSnapshot(for: kinds)
        snapshot.commands = store.settings.widgets.commands
        snapshot.endpoints = store.settings.widgets.endpoints
        if kinds.contains(.fans) {
            snapshot.fans = fans.widgetState
        }
        return snapshot
    }

    @discardableResult
    private func writeWidgetSnapshot() -> Bool {
        var snapshot = makeWidgetSnapshot()
        // Has its own file, which changes with the track.
        snapshot.nowPlaying = nil
        return (try? SnapshotStore().write(snapshot, for: WidgetSnapshot.key)) != nil
    }
}

/// Actions that widgets ask for.
extension AppModel {
    /// Commands from WidgetKit arrive through the shared container; a leftover from before launch is dropped.
    private func observeWidgetCommands() {
        _ = WidgetCommandInbox().drain()
        WidgetCommandSignal.observe { [weak self] in
            MainActor.assumeIsolated { self?.handleWidgetCommands() }
        }
    }

    private func handleWidgetCommands() {
        for command in WidgetCommandInbox().drain() {
            perform(command.action)
        }
    }

    /// Does what a widget button asks. Nothing here trusts the request: each case checks it against current state.
    func perform(_ action: WidgetCommand.Action) {
        switch action {
        case .toggleFanMax, .setFanMode, .selectFanPreset, .setFanCustom:
            fans.perform(action)
        case let .setTodo(id, completed):
            if let item = monitor.agenda.todos.first(where: { $0.id == id }) {
                monitor.agenda.setCompleted(item, completed)
            }
        case let .startTimer(seconds):
            if (1 ... 86400).contains(seconds) {
                monitor.everyday.startTimer(title: loc("Timer"), duration: seconds)
            }
        case let .toggleTimer(id):
            monitor.everyday.update { data in
                if let index = data.timers.firstIndex(where: { $0.id == id }) {
                    data.timers[index].togglePause(at: Date())
                }
            }
        case let .eject(path):
            if monitor.volumes.contains(where: { $0.path == path && $0.isEjectable }) {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: URL(filePath: path))
            }
        case let .runCommand(id):
            runCommand(id, action: action)
            return
        }
        widgetsChanged(by: action)
    }

    /// A command marked "ask first" never runs from a widget, where a stray click would be enough.
    private func runCommand(_ id: UUID, action: WidgetCommand.Action) {
        guard let command = store.settings.widgets.commands.first(where: { $0.id == id && !$0.asksFirst })
        else { return }
        Task {
            await monitor.activity.run(command)
            widgetsChanged(by: action)
        }
    }

    /// Without this the widget would keep showing the old state until the next minute.
    private func widgetsChanged(by action: WidgetCommand.Action) {
        guard writeWidgetSnapshot() else { return }
        for kind in action.affectedKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind.rawValue)
        }
    }
}

extension AppModel {
    func toggleCard(_ module: ModuleID, from window: NSWindow, place: (CGSize) -> CGRect) {
        panels.toggleCard(module, from: window, place: place)
    }

    func hasCard(from window: NSWindow) -> Bool {
        panels.hasCard(from: window)
    }

    func open(_ destination: WidgetDestination) {
        switch destination {
        case let .module(module):
            showPanelAtPointer(module)
        case .widgetSettings:
            panels.closeTransient()
            settingsWindow.showWidgets()
        case let .web(url):
            NSWorkspace.shared.open(url)
        }
    }
}

private extension AppModel {
    func applyPolling() {
        let options = store.settings.module(.cpu)?.options ?? [:]
        monitor.interval = TimeInterval(options.number(ItemOption.samplingSeconds, default: 2))
        monitor.slowsOnBattery = options.flag(ItemOption.slowsOnBattery, default: true)
        monitor.everyday.letsDisplaySleep = store.settings.module(.keepAwake)?.options
            .flag(ItemOption.letsDisplaySleep, default: false) ?? false
        monitor.sunPlaceID = store.settings.module(.sunMoon)?.options[ItemOption.sunPlace].flatMap { Int($0) }
        monitor.everyday.keepAwakeRule = KeepAwakeRule(options: store.settings.module(.keepAwake)?.options ?? [:])
        monitor.everyday.onTimerFinished = { [weak self] in self?.timerFinished($0) }
        monitor.agenda.todoOptions = TodoOptions(options: store.settings.module(.todos)?.options ?? [:])
        applyHardwareChoices()
    }

    /// An empty or missing value means the Mac's own pick.
    func applyHardwareChoices() {
        func chosen(_ module: ModuleID, _ key: String) -> String? {
            store.settings.module(module)?.options[key].flatMap { $0.isEmpty ? nil : $0 }
        }
        monitor.networkInterface = chosen(.network, ItemOption.networkInterface)
        monitor.gpuName = chosen(.gpu, ItemOption.gpuName)
        monitor.volumePath = chosen(.disk, ItemOption.volumePath)
        Format.temperatureUnit = store.settings.module(.sensors)?.options
            .choice(ItemOption.temperatureUnit, default: .system) ?? .system
    }

    func checkAlerts() {
        let settings = store.settings.alerts
        guard settings.isEnabled else { return }
        let fired = thresholds.update(
            battery: monitor.battery,
            averageCPU: monitor.sensors?.averageCPU,
            settings: settings
        )
        for alert in fired {
            post(alert)
        }
    }

    func post(_ alert: ThresholdAlert) {
        let content = UNMutableNotificationContent()
        switch alert {
        case .lowBattery:
            content.title = loc("Battery is low")
            content.body = monitor.battery.map { Format.percent($0.charge) } ?? ""
        case .highTemperature:
            content.title = loc("Mac is running hot")
            content.body = monitor.sensors?.averageCPU.map(Format.temperature) ?? ""
        }
        let request = UNNotificationRequest(identifier: alert.rawValue, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Only what is on screen counts, so the adapter process does not run for nothing.
    var wantsNowPlaying: Bool {
        let widgets = store.settings.widgets.placements.contains { $0.kind == .nowPlaying || $0.kind == .lyrics }
        return isWanted(.nowPlaying) || widgets || nowPlaying.hasSystemWidget
    }

    var wantsLyrics: Bool {
        guard store.settings.module(.nowPlaying)?.options[ModuleOption.onlineLyrics] != "false" else { return false }
        return store.settings.widgets.placements.contains { $0.kind == .lyrics } || nowPlaying.hasSystemLyricsWidget
    }

    func checkSystemWidgets() {
        nowPlaying.checkSystemWidgets { [weak self] in self?.updateDemand() }
    }
}
