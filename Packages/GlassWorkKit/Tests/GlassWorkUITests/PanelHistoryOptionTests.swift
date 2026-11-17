import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct PanelHistoryOptionTests {
    private let volume = DiskVolume(
        name: "Macintosh HD", path: "/", total: 1000, free: 250, isInternal: true, isEjectable: false
    )

    @Test func overviewShowsTheUsedShareOfTheDiskByDefault() {
        #expect(ItemContent.overviewDisk(volume, options: [:]) == Format.percent(0.75))
    }

    @Test func overviewCanShowTheFreeShareInstead() {
        let options = [ItemOption.overviewDisk: OverviewDisk.free.rawValue]
        #expect(ItemContent.overviewDisk(volume, options: options) == Format.percent(0.25))
        #expect(ItemContent.overviewDisk(nil, options: options) == "—")
    }

    @Test func anUnknownDiskChoiceFallsBackToUsed() {
        let options = [ItemOption.overviewDisk: "sideways"]
        #expect(ItemContent.overviewDisk(volume, options: options) == Format.percent(0.75))
    }

    @Test func theGraphSpanReachesTheItem() {
        let monitor = SystemMonitor()
        #expect(ItemContent.cpu(monitor, style: .compact, options: [:]).graphSpan == 60)
        let wide = [ItemOption.graphMinutes: "15"]
        #expect(ItemContent.cpu(monitor, style: .compact, options: wide).graphSpan == 900)
        #expect(ItemContent.content(.gpu, monitor: monitor, style: .compact, options: wide).graphSpan == 900)
    }

    @Test func overviewClickDefaultsToThePanel() {
        #expect([String: String]().choice(ItemOption.overviewClick, default: OverviewClick.panel) == .panel)
        let hub = [ItemOption.overviewClick: OverviewClick.hub.rawValue]
        #expect(hub.choice(ItemOption.overviewClick, default: OverviewClick.panel) == .hub)
    }

    @Test func everyNewOptionHasARowInSettings() {
        let keys = Set(ModuleOptionSpec.all.map(\.id))
        #expect(keys.isSuperset(of: [
            "overview.\(ItemOption.overviewDisk)",
            "overview.\(ItemOption.overviewClick)",
            "cpu.\(ItemOption.graphMinutes)",
            "gpu.\(ItemOption.graphMinutes)",
        ]))
    }
}
