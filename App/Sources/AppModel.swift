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
    private lazy var clipboard = ClipboardController(model: self)
    private lazy var textCapture = TextCaptureController(model: self)
    private(set) lazy var windowTiles = WindowTilesController(model: self)
    private lazy var location = LocationProvider(store: monitor.weather)
    private lazy var nowPlaying = NowPlayingBridge(
        store: monitor.nowPlaying,
        refreshSeconds: store.settings.widgets.refreshSeconds
    )
    private let hotKey = HotKey()
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
        hotKey.onPress = { [weak self] in self?.toggleHub() }
        hotKey.register()
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
            openFanCurves: { [weak self] in self?.showFanCurves() }
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

    func open(_ destination: WidgetDestination) {
        switch destination {
        case let .module(module):
            showPanelAtPointer(module)
        case .widgetSettings:
            panels.closeTransient()
            settingsWindow.showWidgets()
        }
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
        if visibleSection == .apps {
            monitor.refresh()
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
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySettings() }
        }
        applyInfoModules()
        statusBar.apply(store.settings)
        monitor.developer.options = DeveloperOptions(settings: store.settings)
        desktopWidgets.apply(store.settings.widgets)
        dock.apply(store.settings.dock)
        windowTiles.apply(store.settings.windowTiles)
        monitor.temperatureSource = .shown(by: store.settings.module(.sensors)?.options ?? [:])
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
        return mode == .menuBar || (hasOpenPanel && mode != .off)
    }

    private func updateDemand() {
        // Live windows and charts sample on every tick; other system widgets read once a minute.
        let placed = placedWidgetKinds
        var demand = MonitorDemand(widgets: desktopWidgetKinds.union(systemWidgetKinds.filter(\.keepsHistory)))
        let modes = store.settings.modules.filter { $0.mode == .menuBar }.map(\.id)
        let everything = hasOpenPanel
        let showsApps = visibleSection == .apps
        demand.liveApps = everything || showsApps || isQuickQuitOpen
        demand.cpu = demand.cpu || everything || showsApps || modes.contains(.cpu) || modes.contains(.overview)
        demand.memory = demand.memory || everything || showsApps || modes.contains(.memory)
            || modes.contains(.overview)
        demand.network = demand.network || everything || modes.contains(.network)
        demand.disk = demand.disk || everything || modes.contains(.disk) || modes.contains(.eject)
        demand.battery = true
        demand.gpu = demand.gpu || everything || modes.contains(.gpu)
        demand.sensors = demand.sensors || everything || isSettingsOpen || modes.contains(.sensors)
            || modes.contains(.fans) || store.settings.alerts.isEnabled
        demand.processes = everything
        demand.developer = store.settings.developerDemand(panelOpen: everything)
            .union(placed.compactMap(\.developerModule))
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

    /// Screen time counts only after the user turns it on.
    private func observeFrontApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let name = app?.localizedName
            let bundle = app?.bundleURL
            MainActor.assumeIsolated {
                guard let self, self.store.settings.widgets.tracksScreenTime else { return }
                self.monitor.activity.appBecameActive(name, category: Self.category(of: bundle))
            }
        }
        observeLock()
    }

    /// An app run from Downloads or Documents stays uncategorized: opening its bundle would ask for permission.
    private static func category(of bundle: URL?) -> AppCategory {
        guard let bundle, !ProtectedFolders.contains(bundle.path(percentEncoded: false), home: NSHomeDirectory())
        else { return .other }
        let declared = Bundle(url: bundle)?.object(forInfoDictionaryKey: "LSApplicationCategoryType") as? String
        return AppCategory(appStoreCategory: declared)
    }

    /// Locking keeps the display on for a while, so sleep alone would miss most breaks.
    private func observeLock() {
        let center = DistributedNotificationCenter.default()
        let locked = Notification.Name("com.apple.screenIsLocked")
        let unlocked = Notification.Name("com.apple.screenIsUnlocked")
        center.addObserver(forName: locked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAway(true) }
        }
        center.addObserver(forName: unlocked, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenAway(false) }
        }
    }

    private func screenAway(_ isAway: Bool) {
        guard store.settings.widgets.tracksScreenTime else { return }
        if isAway {
            monitor.activity.screenWentAway()
        } else {
            monitor.activity.screenCameBack()
        }
    }

    /// Nothing is read while the Mac sleeps, the screen is off or locked, or another user is active.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let pause: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ]
        let resume: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        // The fan loop keeps running through a locked screen, so only real sleep ends it.
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.fans.willSleep() }
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.fans.didWake() }
        }
        for name in pause {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitor.stop()
                    self?.clipboard.setPaused(true)
                    self?.screenAway(true)
                }
            }
        }
        for name in resume {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitor.start()
                    self?.clipboard.setPaused(false)
                    self?.screenAway(false)
                }
            }
        }
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
                await monitor.activity.refreshGitHub(includesDigest: kinds.contains(.github))
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

private extension AppModel {
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
