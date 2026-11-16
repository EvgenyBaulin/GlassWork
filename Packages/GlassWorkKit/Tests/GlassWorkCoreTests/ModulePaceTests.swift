import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct DeveloperPaceTests {
    @Test func wifiAndVPNSlowDownWhileOnlyTheMenuBarShowsThem() {
        let store = DeveloperStore(runner: FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") })

        store.tick(at: Date(), demand: [], live: false)
        #expect(store.interval(of: .wifi) == 10)
        #expect(store.interval(of: .vpn) == 30)

        store.tick(at: Date(), demand: [], live: true)
        #expect(store.interval(of: .wifi) == 5)
        #expect(store.interval(of: .vpn) == 10)
    }

    @Test func aPanelOpenAnywhereMakesTheDemandLive() {
        var menuBar = MonitorDemand()
        var panel = MonitorDemand()
        panel.developerLive = true

        #expect(menuBar.adding(panel).developerLive)
        menuBar.developerLive = false
        #expect(!menuBar.adding(MonitorDemand()).developerLive)
    }
}

struct RatesPaceTests {
    @Test func eachServiceHasItsOwnPace() {
        #expect(RatesStore.interval(of: .coinGecko) == 15 * 60)
        #expect(RatesStore.interval(of: .cbr) == 60 * 60)
        #expect(RatesStore.interval(of: .frankfurter) == 30 * 60)
    }

    @Test func aScheduleWaitsItsOwnInterval() {
        let start = Date(timeIntervalSince1970: 1_794_850_000)
        var hourly = RefreshSchedule(every: 3600)
        hourly.record(success: true, at: start)

        #expect(!hourly.isDue(at: start.addingTimeInterval(1800)))
        #expect(hourly.isDue(at: start.addingTimeInterval(3600)))
    }

    @Test func aFailureRetriesNoLaterThanTheUsualPace() {
        let start = Date(timeIntervalSince1970: 1_794_850_000)
        var quick = RefreshSchedule(every: 60)
        quick.record(success: false, at: start)

        #expect(quick.isDue(at: start.addingTimeInterval(60)))
    }
}
