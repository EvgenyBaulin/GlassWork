import Foundation
import GlassWorkCore

/// The user's own pause of sampling, set from the menu. Sleep and screen lock pause it separately.
@MainActor
final class UpdatePauseController {
    private unowned let monitor: SystemMonitor
    private var task: Task<Void, Never>?
    private(set) var isPaused = false
    /// Nil while paused indefinitely.
    private(set) var pausedUntil: Date?

    init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    func pause(_ duration: UpdatePause, now: Date = Date()) {
        task?.cancel()
        isPaused = true
        pausedUntil = duration.end(from: now)
        monitor.stop()
        guard let end = pausedUntil else { return }
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(end.timeIntervalSince(now), 0)))
            guard !Task.isCancelled else { return }
            self?.resume()
        }
    }

    func resume() {
        task?.cancel()
        task = nil
        guard isPaused else { return }
        isPaused = false
        pausedUntil = nil
        monitor.start()
    }

    /// The sleep timer does not count time spent asleep, so a wake checks the clock itself.
    func resumeIfDue(now: Date = Date()) {
        if let pausedUntil, pausedUntil <= now {
            resume()
        }
    }
}
