import Foundation
import GlassWorkCore

/// The choices in Settings that change what the widgets show.
extension AppModel {
    /// Read once: dictionaries are added rarely, and a launch picks them up.
    private static let installedDictionaries = SystemDictionaries.installed()

    func applyWidgetData() {
        let widgets = store.settings.widgets
        monitor.activity.configureScreenTime(
            dayStartHour: widgets.dayStartHour,
            excluded: monitor.activity.screenTime.excluded
        )
        monitor.wordOfDay.apply(widgets.wordOfDay, installed: Self.installedDictionaries)
    }

    /// Starts the timer again when the refresh choice in Settings changed.
    func scheduleHeartbeat() {
        let seconds = store.settings.widgets.refreshSeconds
        guard seconds != heartbeatSeconds else { return }
        heartbeatSeconds = seconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeHeartbeat() }
        }
    }
}
