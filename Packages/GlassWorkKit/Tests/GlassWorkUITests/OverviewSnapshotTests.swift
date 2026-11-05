import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// A calm minute: a wavy line per chart, ending at `AppSamples.now`.
@MainActor
private enum OverviewSamples {
    static func points(_ middle: Double, _ swing: Double) -> OverviewReadings.Points {
        (0 ..< 30).map { step in
            History.Point(
                date: AppSamples.now.addingTimeInterval(Double(step - 30) * 2),
                value: middle + swing * sin(Double(step) / 3)
            )
        }
    }

    static var readings: OverviewReadings {
        var readings = OverviewReadings()
        readings.cpu = 0.18
        readings.memoryUsed = 21.4e9
        readings.memoryTotal = 36e9
        readings.diskFree = 182e9
        readings.download = 2.4e6
        readings.upload = 0.3e6
        readings.batteryCharge = 0.84
        readings.celsius = 47
        readings.cpuPoints = points(0.2, 0.1)
        readings.memoryPoints = points(0.6, 0.02)
        readings.downloadPoints = points(2e6, 1.5e6)
        readings.uploadPoints = points(0.4e6, 0.3e6)
        readings.temperaturePoints = points(48, 4)
        readings.apps = AppSamples.apps
        return readings
    }

    static var hoverMoment: Date {
        AppSamples.now.addingTimeInterval(-30)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct OverviewSnapshotTests {
    private func page(_ readings: OverviewReadings, hover: Date? = nil) -> some View {
        OverviewPage(readings: readings, chartHover: hover).frame(width: 660, height: 640)
    }

    @Test(arguments: [true, false])
    func everyReading(dark: Bool) {
        snapshotPanel(page(OverviewSamples.readings), name: "page", dark: dark)
    }

    @Test(arguments: [true, false])
    func chartsUnderThePointer(dark: Bool) {
        snapshotPanel(page(OverviewSamples.readings, hover: OverviewSamples.hoverMoment), name: "hover", dark: dark)
    }

    @Test(arguments: [true, false])
    func aMacWithoutABattery(dark: Bool) {
        var readings = OverviewSamples.readings
        readings.batteryCharge = nil
        snapshotPanel(page(readings), name: "no-battery", dark: dark)
    }

    @Test(arguments: [true, false])
    func beforeTheFirstRead(dark: Bool) {
        snapshotPanel(page(OverviewReadings()), name: "empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func theNarrowestWindow(dark: Bool) {
        let view = OverviewPage(readings: OverviewSamples.readings).frame(width: 540, height: 640)
        snapshotPanel(view, name: "narrow", dark: dark)
    }
}

struct OverviewReadingsTests {
    @Test
    func aMissingReadingShowsADash() {
        let readings = OverviewReadings()
        #expect(readings.cpuText == "–")
        #expect(readings.memoryText == "–")
        #expect(readings.diskText == "–")
        #expect(readings.networkText == "–")
        #expect(readings.temperatureText == "–")
        #expect(readings.batteryText == nil)
    }

    @Test
    func aChargingBatterySaysSo() {
        var readings = OverviewReadings()
        readings.batteryCharge = 0.5
        #expect(readings.batteryText == "50%")
        readings.isCharging = true
        #expect(readings.batteryText == "⚡︎ 50%")
    }
}

struct SectionDemandTests {
    @Test
    func overviewReadsWhatItShows() {
        let demand = MainSection.overview.monitorDemand
        #expect(demand.cpu && demand.memory && demand.network && demand.disk && demand.sensors && demand.liveApps)
        #expect(!demand.gpu && !demand.processes)
    }

    @Test
    func appsReadsLessThanOverview() {
        let demand = MainSection.apps.monitorDemand
        #expect(demand.cpu && demand.memory && demand.liveApps)
        #expect(!demand.network && !demand.disk && !demand.sensors)
    }

    @Test(arguments: [MainSection.clipboard, .windowTiles, .unlock, .widgets, .dock, .settings])
    func otherSectionsReadNothing(section: MainSection) {
        #expect(section.monitorDemand == MonitorDemand())
    }

    @Test
    func addingKeepsBothSides() {
        var first = MonitorDemand()
        first.gpu = true
        first.developer = [.git]
        var second = MonitorDemand()
        second.cpu = true
        second.developer = [.ping]
        let both = first.adding(second)
        #expect(both.gpu && both.cpu)
        #expect(both.developer == [.git, .ping])
        #expect(!both.memory)
    }
}
