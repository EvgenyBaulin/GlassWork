import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// The Network offline state, the CPU core bars without efficiency cores and Overview before its first sample.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct SystemGapsSnapshotTests {
    private func noPoints(_: Metric, _: TieredHistory.Range) -> [History<Double>.Point] {
        []
    }

    @Test(arguments: [false, true])
    func networkOffline(dark: Bool) {
        let counters = [InterfaceCounters(name: "en0", received: 100, sent: 10)]
        let offline = NetworkSample.between(counters, [], seconds: 2, sessionReceived: 5_000_000, sessionSent: 800_000)
        let view = NetworkPanelContent(network: offline, points: noPoints, localIP: nil)
        assertPanel(view, dark: dark, name: "network-offline")
    }

    @Test(arguments: [false, true])
    func coreBarsWithAndWithoutEfficiency(dark: Bool) {
        let info = CPUInfo(brand: "Apple M2 Pro", performanceCores: 6, efficiencyCores: 4)
        let cores: [Double] = [0.8, 0.5, 0.3, 0.2, 0.6, 0.1, 0.4, 0.7, 0.2, 0.9]
        let view = VStack(spacing: 16) {
            CoreBars(cores: cores, info: info)
            CoreBars(cores: cores, info: info, showsEfficiency: false)
        }
        .padding(16)
        assertPanel(view, dark: dark, name: "core-bars-efficiency")
    }

    @Test func overviewShowsDashesBeforeTheFirstSample() {
        let item = ItemContent.overview(SystemMonitor(), options: [ItemOption.showsDisk: "true"])
        #expect(item.figure == "— — —")
    }
}
