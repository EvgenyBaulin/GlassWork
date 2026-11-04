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
    let monitor = SystemMonitor()
    private let fanSensors = FanSensorSource()
    private(set) lazy var fans = makeFans()
    private lazy var panels = PanelController(model: self)
    private lazy var statusBar = StatusBarController(model: self)
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private lazy var desktopWidgets = DesktopWidgetController(model: self)
    private lazy var dock = DockController(model: self)
    private lazy var clipboard = ClipboardController(model: self)
    private lazy var location = LocationProvider(store: monitor.weather)
    private let hotKey = HotKey()
    private var hasOpenPanel = false
    private var isSettingsOpen = false
    private var timer: Timer?
    private var thresholds = ThresholdTracker()

    init() {
        observeSleep()
        observeFrontApp()
        hotKey.onPress = { [weak self] in self?.toggleHub() }
        hotKey.register()
        Task { await monitor.clipboard.load() }
        applySettings()
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
            quitProcess: { process, force in
                kill(process.pid, force ? SIGKILL : SIGTERM)
            },
            updateSettings: { [weak self] change in self?.store.update(change) },
            useClipboardEntry: { [weak self] entry, plain in self?.clipboard.use(entry, plainText: plain) },
            isPasteAllowed: { Accessibility.isTrusted },
            openFanCurves: { [weak self] in self?.showFanCurves() }
        )
    }

    /// Gives the system Dock back when the app quits.
    func prepareToQuit() {
        dock.restoreSystemDock()
    }

    func showSettings(module: ModuleID? = nil) {
        panels.closeTransient()
        settingsWindow.show(module: module)
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

    func toggleHub() {
        statusBar.revealHidden()
        panels.toggleHub(from: statusBar.hubButton)
    }

    func panelsChanged(hasOpenPanel: Bool) {
        self.hasOpenPanel = hasOpenPanel
        updateDemand()
        if hasOpenPanel {
            monitor.refresh()
        }
    }

    private func checkAlerts() {
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

    private func post(_ alert: ThresholdAlert) {
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

    /// The fan and sensor panes show live readings, which no panel may be asking for.
    func settingsChanged(isOpen: Bool) {
        isSettingsOpen = isOpen
        updateDemand()
        if isOpen {
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
        desktopWidgets.apply(store.settings.widgets)
        dock.apply(store.settings.dock)
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
        var demand = MonitorDemand()
        let modes = store.settings.modules.filter { $0.mode == .menuBar }.map(\.id)
        let everything = hasOpenPanel
        demand.cpu = everything || modes.contains(.cpu) || modes.contains(.overview)
        demand.memory = everything || modes.contains(.memory) || modes.contains(.overview)
        demand.network = everything || modes.contains(.network)
        demand.disk = everything || modes.contains(.disk) || modes.contains(.eject)
        demand.battery = true
        demand.gpu = everything || modes.contains(.gpu)
        demand.sensors = everything || isSettingsOpen || modes.contains(.sensors) || modes.contains(.fans)
            || store.settings.alerts.isEnabled
        demand.processes = everything
        demand.devices = everything || modes.contains(.deviceBatteries)
        monitor.demand = demand
        monitor.weather.isActive = isWanted(.weather)
        monitor.rates.isActive = isWanted(.rates)
    }

    func closePanels() {
        panels.closeTransient()
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
            MainActor.assumeIsolated {
                guard let self, self.store.settings.widgets.tracksScreenTime else { return }
                self.monitor.activity.appBecameActive(name)
            }
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
                }
            }
        }
        for name in resume {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.monitor.start()
                    self?.clipboard.setPaused(false)
                }
            }
        }
    }

    private func writeHeartbeat() {
        Task {
            await monitor.activity.check(store.settings.widgets.endpoints)
            await monitor.activity.refreshGitHub()
            var snapshot = await monitor.widgetSnapshot()
            snapshot.commands = store.settings.widgets.commands
            snapshot.endpoints = store.settings.widgets.endpoints
            guard (try? SnapshotStore().write(snapshot, for: WidgetSnapshot.key)) != nil else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
