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
    private lazy var panels = PanelController(model: self)
    private lazy var statusBar = StatusBarController(model: self)
    private lazy var settingsWindow = SettingsWindowController(model: self)
    private let hotKey = HotKey()
    private var hasOpenPanel = false
    private var timer: Timer?
    private var thresholds = ThresholdTracker()

    init() {
        observeSleep()
        hotKey.onPress = { [weak self] in self?.toggleHub() }
        hotKey.register()
        applySettings()
        monitor.onUpdate = { [weak self] in
            self?.statusBar.refreshItems()
            self?.checkAlerts()
        }
        monitor.start()
        writeHeartbeat()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeHeartbeat() }
        }
        if !store.settings.welcomeCompleted {
            settingsWindow.showWelcome()
        }
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
            }
        )
    }

    func showSettings(module: ModuleID? = nil) {
        panels.closeTransient()
        settingsWindow.show(module: module)
    }

    func togglePanel(_ module: ModuleID, from button: NSStatusBarButton) {
        panels.toggle(module, from: button)
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

    /// Runs now and again whenever settings change.
    private func applySettings() {
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in self?.applySettings() }
        }
        statusBar.apply(store.settings)
        updateDemand()
    }

    private func updateDemand() {
        var demand = MonitorDemand()
        let modes = store.settings.modules.filter { $0.mode == .menuBar }.map(\.id)
        let everything = hasOpenPanel
        demand.cpu = everything || modes.contains(.cpu) || modes.contains(.overview)
        demand.memory = everything || modes.contains(.memory) || modes.contains(.overview)
        demand.network = everything || modes.contains(.network)
        demand.disk = everything || modes.contains(.disk)
        demand.battery = true
        demand.gpu = everything || modes.contains(.gpu)
        demand.sensors = everything || modes.contains(.sensors) || store.settings.alerts.isEnabled
        demand.processes = everything
        monitor.demand = demand
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
        for name in pause {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.monitor.stop() }
            }
        }
        for name in resume {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.monitor.start() }
            }
        }
    }

    private func writeHeartbeat() {
        let now = Date()
        let beat = Heartbeat(updatedAt: now, bootTime: SystemClock.bootTime() ?? now)
        guard (try? SnapshotStore().write(beat, for: Heartbeat.key)) != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
