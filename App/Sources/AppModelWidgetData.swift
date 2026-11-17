import Foundation
import GlassWorkCore

/// The choices in Settings that change what the widgets show.
extension AppModel {
    private static let sunAppearance = SunAppearanceScheduler()

    /// Appearance follows the sun by the place Sun and Moon uses: a city in Weather, or the current location.
    func applySunAppearance() {
        let follows = store.settings.module(.appearance)?.options.flag(ItemOption.followsSun, default: false) ?? false
        Self.sunAppearance.apply(isOn: follows && store.settings.module(.appearance)?.mode != .off) { [weak self] in
            self?.monitor.sunPlace
        }
    }

    func applyWidgetData() {
        applySunAppearance()
        let widgets = store.settings.widgets
        monitor.activity.onScreenTimeReset = { [weak self] in
            Task { @MainActor in await self?.publishSystemWidgets() }
        }
        monitor.activity.configureScreenTime(
            dayStartHour: widgets.dayStartHour,
            excluded: monitor.activity.screenTime.excluded
        )
        monitor.wordOfDay.onFilled = { [weak self] in
            Task { @MainActor in await self?.publishSystemWidgets() }
        }
        DictionaryCatalog.shared.load { [weak self] in self?.applyWidgetData() }
        monitor.wordOfDay.apply(widgets.wordOfDay, installed: DictionaryCatalog.shared.installed)
    }

    /// Starts the timer again when the refresh choice in Settings changed.
    func scheduleHeartbeat() {
        let seconds = store.settings.widgets.heartbeatSeconds
        guard seconds != heartbeatSeconds else { return }
        heartbeatSeconds = seconds
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.writeHeartbeat() }
        }
    }
}

/// The dictionaries on this Mac. Looking for them reads folders, so the first look runs off the main thread;
/// until it ends only the system default is offered.
@MainActor
final class DictionaryCatalog {
    static let shared = DictionaryCatalog()

    private(set) var installed: [SystemDictionary] = []
    private var isLoading = false

    /// Starts the scan once and calls `done` when it has finished.
    func load(done: @escaping @MainActor () -> Void) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            installed = await Task.detached { SystemDictionaries.installed() }.value
            done()
        }
    }
}
