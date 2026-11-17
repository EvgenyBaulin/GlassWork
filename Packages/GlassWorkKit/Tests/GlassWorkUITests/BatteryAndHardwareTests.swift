import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct BatteryAndHardwareTests {
    // MARK: Hardware availability

    @Test func aMacWithoutABatteryHidesBattery() {
        let desktop = HardwareAvailability(hasBattery: false)
        #expect(!ModuleID.battery.isAvailable(on: desktop))
        #expect(ModuleID.battery.isAvailable(on: .all))
        #expect(ModuleID.cpu.isAvailable(on: desktop))
    }

    @Test func aMacWithoutWiFiHidesWiFi() {
        let wired = HardwareAvailability(hasWiFi: false)
        #expect(!ModuleID.wifi.isAvailable(on: wired))
        #expect(ModuleID.wifi.isAvailable(on: .all))
        #expect(ModuleID.battery.isAvailable(on: wired))
    }

    @Test func aMacWithoutFansHidesFans() {
        #expect(!ModuleID.fans.isAvailable(on: HardwareAvailability(hasFans: false)))
        #expect(ModuleID.fans.isAvailable(on: .all))
    }

    // MARK: Tooltip

    private let since = Date(timeIntervalSince1970: 1_800_000_000)
    private let timeStyle = Date.FormatStyle(
        date: .omitted,
        time: .shortened,
        locale: Locale(identifier: "en_US"),
        timeZone: .gmt
    )

    @Test func tooltipShowsValueRangeAndStart() {
        let extremes = ItemTooltip.Extremes([0.04, 0.91, 0.23], since: since)
        let text = ItemTooltip.text(
            title: "CPU",
            figure: "23%",
            extremes: extremes,
            format: { Format.percent($0) },
            timeStyle: timeStyle
        )
        #expect(text == "CPU 23% · \(loc("min")) 4% · \(loc("max")) 91% \(loc("since \(since.formatted(timeStyle))"))")
        #expect(text.contains("min"))
        #expect(text.contains("4%") && text.contains("91%"))
    }

    @Test func tooltipWithoutHistoryKeepsContext() {
        #expect(ItemTooltip.Extremes([], since: nil) == nil)
        let text = ItemTooltip.text(
            title: "Network",
            figure: "↓ 1 MB/s",
            extremes: nil,
            format: { "\($0)" },
            secondLine: "↑ 2 KB/s",
            detail: "en0"
        )
        #expect(text == "Network ↓ 1 MB/s\n↑ 2 KB/s\nen0")
    }

    @Test func tooltipOfAFreshModuleUsesTheMonitorHistory() {
        let monitor = SystemMonitor()
        let renderer = MenuBarItemRenderer(module: .battery, style: .figure, numbers: .precise, monitor: monitor)
        // Battery has no metric, so there is no range, only the figure.
        #expect(renderer.tooltip().hasPrefix(ModuleID.battery.title))
        #expect(!renderer.tooltip().contains(loc("max")))
    }

    // MARK: Battery glyph

    @Test func batteryGlyphFollowsChargeAndPower() {
        func glyph(charging: Bool, onAC: Bool, charge: Double = 0.6) -> ItemGlyph? {
            let sample = BatterySample(charge: charge, isCharging: charging, isOnAC: onAC)
            return ItemContent.battery(sample, style: .compact, options: [:]).glyph
        }
        #expect(glyph(charging: false, onAC: false) == .battery(level: 0.6, state: .discharging))
        #expect(glyph(charging: true, onAC: true) == .battery(level: 0.6, state: .charging))
        #expect(glyph(charging: false, onAC: true, charge: 1) == .battery(level: 1, state: .pluggedIn))
        #expect(ItemContent.battery(nil, style: .compact, options: [:]).glyph == nil)
    }

    // MARK: Energy apps

    @Test func energyAppsAreTheBusiestFiveAboveTheThreshold() {
        let apps = (0 ..< 8).map {
            AppUsage(id: "app\($0)", pid: Int32($0), name: "App \($0)", cpu: Double($0) * 10, memory: 0)
        } + [AppUsage(id: "idle", pid: 99, name: "Idle", cpu: 0.4, memory: 0)]
        let top = BatteryPanelContent.energyApps(apps)
        #expect(top.map(\.id) == ["app7", "app6", "app5", "app4", "app3"])
        #expect(BatteryPanelContent.energyApps([apps[0], apps[8]]).isEmpty)
    }
}
