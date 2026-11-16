import Foundation
import GlassWorkCore

/// Redraws the menu bar items that count seconds once a second, on the second, apart from the 2 s reading loop:
/// at 2 s a countdown skips every other second.
@MainActor
final class SecondTicker {
    /// Owner's table (2026-11-16): timers and the stopwatch while they run, Ends In always.
    static let modules: Set<ModuleID> = [.timers, .stopwatch, .endsIn]

    private let tick: (Set<ModuleID>) -> Void
    private var timer: Timer?
    private var shown: Set<ModuleID> = []

    init(tick: @escaping (Set<ModuleID>) -> Void) {
        self.tick = tick
    }

    /// Runs only while one of the modules is in the menu bar.
    func follow(_ modules: Set<ModuleID>) {
        shown = modules.intersection(Self.modules)
        guard !shown.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        let now = Date()
        let next = now.timeIntervalSinceReferenceDate.rounded(.up)
        let created = Timer(
            fire: Date(timeIntervalSinceReferenceDate: next),
            interval: 1,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        created.tolerance = 0.05
        RunLoop.main.add(created, forMode: .common)
        timer = created
    }

    private func fire() {
        tick(shown)
    }
}
