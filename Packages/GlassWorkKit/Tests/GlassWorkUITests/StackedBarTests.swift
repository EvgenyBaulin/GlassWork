import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

private let gib: UInt64 = 1 << 30

private let parts = [
    StackedPart(title: "App", bytes: 6 * gib, tint: Palette.green),
    StackedPart(title: "Wired", bytes: 3 * gib, tint: Palette.orange),
    StackedPart(title: "Compressed", bytes: 0, tint: Palette.purple),
    StackedPart(title: "Cached", bytes: 4 * gib, tint: Palette.cyan),
]
private let total = 16 * gib

struct StackedBarHitTests {
    @Test func spansFollowTheSizesWithOnePixelBetween() {
        let spans = StackedBarLayout.spans(parts, total: total, width: 160)
        #expect(spans[0] == 0 ... 60)
        #expect(spans[1] == 61 ... 91)
        #expect(spans[3] == 93 ... 133)
    }

    @Test func aPointFindsItsPart() {
        #expect(StackedBarLayout.index(at: 10, parts: parts, total: total, width: 160) == 0)
        #expect(StackedBarLayout.index(at: 70, parts: parts, total: total, width: 160) == 1)
        #expect(StackedBarLayout.index(at: 100, parts: parts, total: total, width: 160) == 3)
    }

    @Test func theEmptyEndOfTheBarHitsNothing() {
        #expect(StackedBarLayout.index(at: 150, parts: parts, total: total, width: 160) == nil)
    }

    @Test func aPartWithoutBytesIsNeverHit() {
        // Its zero-width span sits at 92; the point lands on nothing rather than on "Compressed".
        #expect(StackedBarLayout.index(at: 92, parts: parts, total: total, width: 160) != 2)
    }

    @Test func theTooltipNamesThePartWithSizeAndShare() {
        let row = StackedBarLayout.row(for: parts[0], total: total)
        #expect(row.title == "App")
        #expect(row.value == "\(Format.bytes(Double(6 * gib), style: .precise)) · 37.5%")
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct StackedBarSnapshotTests {
    private func snapshot(_ view: some View, name: String) {
        for dark in [true, false] {
            let host = NSHostingView(
                rootView: view
                    .padding(40)
                    .frame(width: 300, height: 160, alignment: .topLeading)
                    .background(dark ? Color(white: 0.12) : Color(white: 0.96))
                    .environment(\.colorScheme, dark ? .dark : .light)
            )
            host.frame = CGRect(x: 0, y: 0, width: 300, height: 160)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
            withSnapshotTesting(record: record ? .all : .missing) {
                assertSnapshot(of: host, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
            }
        }
    }

    @Test func hoveringAPartShowsItsReadout() {
        snapshot(StackedBar(parts: parts, total: total, initialHover: CGPoint(x: 30, y: 4)), name: "memory-bar-app")
    }

    @Test func hoveringTheLastPartShowsItsReadout() {
        snapshot(StackedBar(parts: parts, total: total, initialHover: CGPoint(x: 150, y: 4)), name: "memory-bar-cached")
    }

    @Test func aFloatingPanelFollowsTheWindowWidth() {
        let panel = PanelFrame(module: .memory, subtitle: "16 GB", footerTitle: "Open Activity Monitor") {
            StackedBar(parts: parts, total: total)
        }
        .environment(\.panelDetached, true)
        assertPanel(panel, width: 460, dark: true, name: "detached-panel")
        assertPanel(panel, width: 460, dark: false, name: "detached-panel")
    }
}
