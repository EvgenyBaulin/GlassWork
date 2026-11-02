import Foundation
import GlassWorkCore
import Observation
import WidgetKit

/// Writes a heartbeat into the shared container so widgets can show live data.
@MainActor
@Observable
final class HeartbeatWriter {
    private(set) var lastWrite: Date?
    private(set) var lastError: String?
    private let store = SnapshotStore()
    private var timer: Timer?

    init() {
        write()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.write() }
        }
    }

    func write() {
        let now = Date()
        let beat = Heartbeat(updatedAt: now, bootTime: SystemClock.bootTime() ?? now)
        do {
            try store.write(beat, for: Heartbeat.key)
            lastWrite = now
            lastError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
