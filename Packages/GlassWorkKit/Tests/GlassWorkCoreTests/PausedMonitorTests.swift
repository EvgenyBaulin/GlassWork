import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct PausedMonitorTests {
    private func makeMonitor() -> SystemMonitor {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let monitor = SystemMonitor(everyday: EverydayStore(store: SnapshotStore(directory: folder)))
        monitor.pausedInterval = 0.01
        return monitor
    }

    private func waitForTimers(in monitor: SystemMonitor, count: Int) async {
        for _ in 0 ..< 300 where monitor.everyday.data.timers.count != count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aTimerRingsWhileTheMonitorIsPaused() async {
        let monitor = makeMonitor()
        var rung: [String] = []
        monitor.everyday.onTimerFinished = { rung.append($0.title) }
        monitor.everyday.startTimer(title: "Tea", duration: 0)

        monitor.stop()
        await waitForTimers(in: monitor, count: 0)

        #expect(rung == ["Tea"])
    }

    @Test func aTimerRingsOnceWhenThePauseEnds() async {
        let monitor = makeMonitor()
        var rung = 0
        monitor.everyday.onTimerFinished = { _ in rung += 1 }

        monitor.stop()
        monitor.start()
        monitor.stop()
        monitor.everyday.startTimer(title: "Tea", duration: 0)
        await waitForTimers(in: monitor, count: 0)
        try? await Task.sleep(for: .milliseconds(50))

        #expect(rung == 1)
    }
}
