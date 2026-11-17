import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

private let now = Date(timeIntervalSince1970: 1_793_750_000)

/// Charts with the cursor on them: the shared tooltip next to the hovered part. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct HoverSnapshotTests {
    private func snapshot(_ view: some View, width: CGFloat, height: CGFloat, name: String) {
        for dark in [true, false] {
            let scheme: ColorScheme = dark ? .dark : .light
            let host = NSHostingView(
                rootView: view
                    .padding(40)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .background(dark ? Color(white: 0.12) : Color(white: 0.96))
                    .environment(\.colorScheme, scheme)
            )
            host.frame = CGRect(x: 0, y: 0, width: width, height: height)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
            withSnapshotTesting(record: record ? .all : .missing) {
                assertSnapshot(of: host, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
            }
        }
    }

    private func ring(hover: CGPoint) -> some View {
        RingGauge(
            value: 0.62,
            tint: Palette.cyan,
            lineWidth: 10,
            readout: RingReadout(usedTitle: "Free", freeTitle: "Used", usedValue: "310 GB", freeValue: "190 GB"),
            initialHover: hover
        ) {
            Text("310 GB").font(.system(size: 16, weight: .semibold, design: .rounded))
        }
        .frame(width: 112, height: 112)
    }

    @Test func ringShowsTheUsedPartUnderTheCursor() {
        snapshot(ring(hover: CGPoint(x: 87, y: 15)), width: 300, height: 240, name: "ring-used")
    }

    @Test func ringShowsTheFreePartUnderTheCursor() {
        snapshot(ring(hover: CGPoint(x: 3, y: 51)), width: 300, height: 240, name: "ring-free")
    }

    @Test func limitBarShowsItsBreakdown() {
        let window = AIWindow(kind: .week, used: 0.42, resetsAt: now.addingTimeInterval(2 * 86400))
        let bar = ThinBar(
            value: 0.42,
            tint: Palette.green,
            readout: AIWindowText.breakdown(window, now: now, tint: Palette.green),
            initialHover: CGPoint(x: 60, y: 4)
        )
        .frame(width: 220)
        snapshot(bar, width: 320, height: 130, name: "limit-bar")
    }

    @Test func dotRangeShowsTheDotAndTheRange() {
        let range = DateInterval(start: Date(timeIntervalSince1970: 1_793_000_000), duration: 30 * 86400)
        let dots = WidgetDotBar(value: 0.4, tint: Palette.orange, range: range, initialHover: CGPoint(x: 90, y: 3))
            .frame(width: 240)
        snapshot(dots, width: 340, height: 130, name: "dot-range")
    }

    @Test func yearDotShowsDateWeekdayAndRelativeTime() {
        let widget = YearInDotsWidget(now: now, initialHoverDay: 40)
            .frame(width: 170, height: 150, alignment: .topLeading)
        snapshot(widget, width: 460, height: 260, name: "year-dot")
    }

    @Test func heatMapUsesTheSharedTooltip() {
        let first = Date(timeIntervalSince1970: 1_780_000_000)
        let days = (0 ..< 26 * 7).map { offset in
            ContributionDay(
                date: first.addingTimeInterval(Double(offset) * 86400).formatted(.iso8601.year().month().day()),
                contributions: offset % 9
            )
        }
        let map = HeatMap(days: days, initialHover: CGPoint(x: 94, y: 24))
            .frame(width: 270, height: 68)
        snapshot(map, width: 360, height: 190, name: "heat-map")
    }
}
