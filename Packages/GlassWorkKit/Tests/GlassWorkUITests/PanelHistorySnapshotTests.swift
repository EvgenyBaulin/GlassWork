import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// The CPU panel with a hour of history and the Sensors panel on a long range, with the cursor on a chart.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct PanelHistorySnapshotTests {
    private static let now = AppSamples.now

    private static let cpu = CPUSample(
        total: 0.31, user: 0.2, system: 0.11, idle: 0.69, cores: [0.5, 0.4, 0.3, 0.2, 0.3, 0.1, 0.05, 0.02]
    )

    private static func hourOfCPU(_: TieredHistory.Range) -> [History<Double>.Point] {
        (0 ... 60).map { minute in
            .init(
                date: now.addingTimeInterval(Double(minute - 60) * 60),
                value: 0.3 + 0.2 * sin(Double(minute) / 5)
            )
        }
    }

    private func panel(reachesBeforeStart: Bool, hover: Date?) -> some View {
        CPUPanelContent(
            cpu: Self.cpu,
            info: CPUInfo(brand: "Apple M2 Pro", performanceCores: 4, efficiencyCores: 4),
            loadAverage: [2.1, 1.8, 1.5],
            apps: AppSamples.apps,
            history: AppSamples.history,
            options: [:],
            points: Self.hourOfCPU,
            reachesBeforeStart: { _ in reachesBeforeStart },
            range: .hour,
            initialHover: hover
        )
    }

    @Test(arguments: [false, true])
    func cpuChartShowsTheBusiestAppUnderTheCursor(dark: Bool) {
        let hover = Self.now.addingTimeInterval(-25 * 60)
        assertPanel(panel(reachesBeforeStart: true, hover: hover), dark: dark, name: "cpu-hover-since-launch")
    }

    @Test(arguments: [false, true])
    func cpuSummaryWithoutTheLaunchNote(dark: Bool) {
        assertPanel(panel(reachesBeforeStart: false, hover: nil), dark: dark, name: "cpu-summary")
    }

    /// Three hours of readings, one every 30 seconds, ending at the sample time.
    private static var longTracker: SensorTracker {
        var tracker = SensorTracker()
        let groups = Set(SensorGroup.allCases)
        for step in 0 ..< 360 {
            let wave = sin(Double(step) / 40)
            let sample = SensorSample(
                readings: [
                    SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 62 + 22 * wave),
                    SensorReading(key: "Tp09", group: .cpuPerformance, celsius: 55 + 10 * wave),
                    SensorReading(key: "Tg0f", group: .gpu, celsius: 45 + 8 * wave),
                    SensorReading(key: "TB0T", group: .battery, celsius: 31),
                ],
                fans: []
            )
            tracker.apply(sample, groups: groups, at: sampleNow.addingTimeInterval(Double(step - 360) * 30))
        }
        return tracker
    }

    @Test(arguments: [false, true])
    func sensorsOnTheDayRangeShowZoneAndPeak(dark: Bool) {
        let sample = SensorSample(
            readings: [
                SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 71),
                SensorReading(key: "Tp09", group: .cpuPerformance, celsius: 56),
                SensorReading(key: "Tg0f", group: .gpu, celsius: 47),
                SensorReading(key: "TB0T", group: .battery, celsius: 31),
            ],
            fans: []
        )
        let view = SensorsPanelContent(
            sample: sample,
            tracker: Self.longTracker,
            groups: [.cpuPerformance, .gpu, .battery],
            hoveredKey: "Tp01",
            range: .day,
            now: sampleNow
        )
        assertPanel(view, dark: dark, name: "sensors-day-hover")
    }
}
