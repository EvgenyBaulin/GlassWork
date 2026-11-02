import AppKit
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
/// Set `GW_SKIP_SNAPSHOTS=1` (CI does) to skip them; `GW_RECORD_SNAPSHOTS=1` re-records.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct RingGaugeSnapshotTests {
    @Test func ringAtSixtyTwoPercent() {
        let view = RingGauge(value: 0.62, tint: .green) {
            Text("62%").font(.title2.bold())
        }
        .frame(width: 120, height: 120)
        .background(Color(white: 0.12))
        .environment(\.colorScheme, .dark)

        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 120, height: 120)
        host.appearance = NSAppearance(named: .darkAqua)

        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: host, as: .image(precision: 0.98))
        }
    }
}
