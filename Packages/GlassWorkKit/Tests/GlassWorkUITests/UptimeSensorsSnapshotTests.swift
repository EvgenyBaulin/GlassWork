import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

/// The Uptime panel with its sleep history and the Sensors panel with sparklines.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct UptimeSensorsSnapshotTests {
    private static let boot = sampleNow.addingTimeInterval(-3 * 86400)

    private static var history: SleepHistory {
        var history = SleepHistory(boot: boot)
        let hour = 3600.0
        history.record(.sleep, at: boot.addingTimeInterval(9 * hour))
        history.record(.wake, at: boot.addingTimeInterval(17 * hour))
        history.record(.sleep, at: boot.addingTimeInterval(30 * hour))
        history.record(.wake, at: boot.addingTimeInterval(41 * hour))
        history.record(.sleep, at: boot.addingTimeInterval(55 * hour))
        history.record(.wake, at: boot.addingTimeInterval(64 * hour))
        return history
    }

    @Test(arguments: [false, true])
    func uptimeWithHistory(dark: Bool) {
        let view = UptimePanelContent(boot: Self.boot, history: Self.history, now: sampleNow)
        assertPanel(view, dark: dark, name: "uptime-history")
    }

    @Test(arguments: [false, true])
    func uptimeWithoutSleeps(dark: Bool) {
        let view = UptimePanelContent(boot: Self.boot, history: SleepHistory(boot: Self.boot), now: sampleNow)
        assertPanel(view, dark: dark, name: "uptime-no-sleeps")
    }

    private static func sample(step: Int) -> SensorSample {
        let wave = sin(Double(step) / 5)
        return SensorSample(
            readings: [
                SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 52 + 8 * wave),
                SensorReading(key: "Tp09", group: .cpuPerformance, celsius: 48 + 3 * wave),
                SensorReading(key: "Tg0f", group: .gpu, celsius: 45 + Double(step) / 4),
                SensorReading(key: "TB0T", group: .battery, celsius: 31),
            ],
            fans: []
        )
    }

    private static var tracker: SensorTracker {
        var tracker = SensorTracker()
        let groups = Set(SensorGroup.allCases)
        for step in 0 ..< 40 {
            tracker.apply(sample(step: step), groups: groups, at: sampleNow.addingTimeInterval(Double(step - 40) * 5))
        }
        return tracker
    }

    private static let groups: [SensorGroup] = [.cpuPerformance, .gpu, .battery]

    @Test(arguments: [false, true])
    func sensorsWithSparklines(dark: Bool) {
        let view = SensorsPanelContent(
            sample: Self.sample(step: 39), tracker: Self.tracker, groups: Self.groups, now: sampleNow
        )
        assertPanel(view, dark: dark, name: "sensors-sparklines")
    }

    @Test(arguments: [false, true])
    func sensorSparklineHover(dark: Bool) {
        let view = SensorsPanelContent(
            sample: Self.sample(step: 39), tracker: Self.tracker, groups: Self.groups, hoveredKey: "Tp01",
            now: sampleNow
        )
        assertPanel(view, dark: dark, name: "sensors-sparkline-hover")
    }

    @Test(arguments: [false, true])
    func sensorKeysHidden(dark: Bool) {
        let view = SensorsPanelContent(
            sample: Self.sample(step: 39), tracker: Self.tracker, groups: Self.groups, showsKeys: false,
            now: sampleNow
        )
        assertPanel(view, dark: dark, name: "sensors-no-keys")
    }
}
