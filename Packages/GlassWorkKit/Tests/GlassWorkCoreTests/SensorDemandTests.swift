import Foundation
@testable import GlassWorkCore
import Testing

struct SensorPaceTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func theFirstReadIsAlwaysDue() {
        var pace = SensorPace()
        let isDue = pace.isDue(.summary, at: start)
        #expect(isDue)
    }

    @Test
    func everyThirdTickAtTheUsualPace() {
        var pace = SensorPace()
        let due = (0 ..< 7).map { pace.isDue(.summary, at: start.addingTimeInterval(Double($0) * 2)) }
        #expect(due == [true, false, false, true, false, false, true])
    }

    @Test
    func aTickLandingALittleEarlyStillCounts() {
        var pace = SensorPace()
        _ = pace.isDue(.summary, at: start)
        let isDue = pace.isDue(.full, at: start.addingTimeInterval(SensorPace.interval - 0.1))
        #expect(isDue)
    }

    @Test
    func aListOnScreenGetsEveryTick() {
        var pace = SensorPace()
        let due = (0 ..< 3).map { pace.isDue(.live, at: start.addingTimeInterval(Double($0) * 2)) }
        #expect(due == [true, true, true])
    }
}

struct SensorChoiceKeyTests {
    @Test
    func anAverageNeedsItsWholeGroup() {
        #expect(SensorChoice.averageCPU.covers("Tp01"))
        #expect(SensorChoice.averageCPU.covers("Te05"))
        #expect(!SensorChoice.averageCPU.covers("Tg0a"))
        #expect(SensorChoice.hottestCPU.covers("Tp01"))
        #expect(SensorChoice.averageGPU.covers("Tg0a"))
        #expect(SensorChoice.averageSoC.covers("Ts0a"))
    }

    @Test
    func oneSensorNeedsOnlyItself() {
        #expect(SensorChoice.sensor("TB0T").covers("TB0T"))
        #expect(!SensorChoice.sensor("TB0T").covers("TB1T"))
    }

    /// The summary leaves keys out, so every choice must still give the figure the full list gives.
    @Test(arguments: [SensorChoice.averageCPU, .hottestCPU, .averageGPU, .averageSoC, .sensor("TB0T")])
    func aSummaryAnswersLikeTheFullList(choice: SensorChoice) {
        let keys = ["Tp01", "Tp05", "Te05", "Tg0a", "Tg0b", "Ts0a", "TB0T", "TH0a", "TaLP"]
        let all = keys.enumerated().map { index, key in
            SensorReading(key: key, group: SensorGroup(key: key), celsius: 40 + Double(index))
        }
        let full = SensorSample(readings: all, fans: [])
        let summary = SensorSample(readings: all.filter { choice.covers($0.key) }, fans: [])
        #expect(summary.celsius(for: choice) == full.celsius(for: choice))
    }
}

@MainActor
struct SensorDemandTests {
    @Test
    func widgetsAskForEverySensorAtTheCalmPace() {
        let demand = MonitorDemand(widgets: [.temperature])
        #expect(demand.sensors)
        #expect(demand.sensorDetail == .full)
    }

    @Test
    func aWidgetWithoutSensorsAsksForNoDetail() {
        #expect(MonitorDemand(widgets: [.network]).sensorDetail == .summary)
    }

    @Test
    func addingKeepsTheHigherDetail() {
        var live = MonitorDemand()
        live.sensorDetail = .live
        #expect(MonitorDemand(widgets: [.fans]).adding(live).sensorDetail == .live)
    }

    /// A summary in the menu bar is not enough for a widget, which lists more than the bar shows.
    @Test
    func aWidgetStillReadsWhenTheBarOnlyHasASummary() {
        var bar = MonitorDemand()
        bar.sensors = true
        let rest = MonitorDemand(widgets: [.temperature]).subtracting(bar)
        #expect(rest.sensors)
        #expect(rest.sensorDetail == .full)
    }

    @Test
    func aWidgetAddsNothingWhenEverySensorIsReadAlready() {
        var live = MonitorDemand()
        live.sensors = true
        live.sensorDetail = .live
        #expect(!MonitorDemand(widgets: [.temperature]).subtracting(live).sensors)
    }
}
