import Foundation
import GlassWorkCore

/// Switches Dock presets when a scheduled rule starts. A preset picked by hand stays until the next rule starts;
/// at launch the rule in force is applied once.
@MainActor
final class DockPresetScheduler {
    private let apply: (DockPresetRule) -> Void
    private var timer: Timer?
    /// The rule and start last applied, so each start switches once.
    private var applied: (id: UUID, start: Date)?

    private static let interval: TimeInterval = 30

    init(apply: @escaping (DockPresetRule) -> Void) {
        self.apply = apply
    }

    func follow(_ settings: DockSettings) {
        guard settings.isEnabled, settings.followsSchedule, !settings.schedule.isEmpty else {
            timer?.invalidate()
            timer = nil
            applied = nil
            return
        }
        check(settings.schedule)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(settings.schedule) }
        }
    }

    private func check(_ rules: [DockPresetRule]) {
        guard let current = DockPresetSchedule.current(at: Date(), rules: rules) else { return }
        if let applied, applied.id == current.rule.id, applied.start == current.start {
            return
        }
        applied = (current.rule.id, current.start)
        apply(current.rule)
    }
}
