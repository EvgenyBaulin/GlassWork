import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct ChartSnapshotTests {
    private func points(_ values: [Double]) -> [History<Double>.Point] {
        var history = History<Double>(capacity: values.count)
        for (index, value) in values.enumerated() {
            history.append(value, at: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 2))
        }
        return history.points
    }

    private func snapshot(_ view: some View, width: CGFloat, height: CGFloat, name: String) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark).background(Color(white: 0.12)))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: .darkAqua)
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: host, as: .image(precision: 0.98), named: name)
        }
    }

    @Test func tooltipShowsEverySeries() {
        let tooltip = ChartTooltip(date: Date(timeIntervalSince1970: 1_800_000_000), rows: [
            .init(id: "down", title: "Download", value: "12.4 MB/s", color: Palette.teal),
            .init(id: "up", title: "Upload", value: "1.1 MB/s", color: Palette.blue),
        ])
        snapshot(tooltip.frame(width: 170), width: 190, height: 90, name: "tooltip")
    }

    @Test func sparklineFillsItsFrame() {
        snapshot(
            Sparkline(values: [0.1, 0.4, 0.2, 0.8, 0.5], domain: 0 ... 1, color: Palette.blue)
                .frame(width: 120, height: 32),
            width: 120,
            height: 32,
            name: "sparkline"
        )
    }

    @Test func seriesSnapToTheNearestPoint() {
        let series = ChartSeries(id: "cpu", title: "CPU", color: .blue, points: points([1, 2, 3])) { "\($0)" }
        let date = Date(timeIntervalSince1970: 1_800_000_002.9)
        #expect(series.nearest(to: date)?.value == 2)
    }
}
