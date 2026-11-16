import Foundation
@testable import GlassWorkCore
import Testing

struct MetricPaceTests {
    private let start = Date(timeIntervalSince1970: 1_794_850_000)

    @Test func theMenuBarTableFollowsTheModules() {
        let memoryOnly = SampleKind.menuBarPaces(for: [.memory])
        #expect(memoryOnly[.memory] == 10)
        #expect(memoryOnly[.cpu] == 5)
        #expect(memoryOnly[.gpu] == 5)
        #expect(memoryOnly[.diskActivity] == 5)
        #expect(memoryOnly[.sensors] == 10)

        let busy = SampleKind.menuBarPaces(for: [.cpu, .overview, .fans])
        #expect(busy[.cpu] == nil)
        #expect(busy[.memory] == 5)
        #expect(busy[.sensors] == 5)
    }

    @Test func aPaceWaitsWithHalfASecondOfSlack() {
        #expect(SampleKind.isDue(last: nil, pace: 10, at: start))
        #expect(SampleKind.isDue(last: start, pace: nil, at: start))
        #expect(!SampleKind.isDue(last: start, pace: 10, at: start.addingTimeInterval(8)))
        #expect(SampleKind.isDue(last: start, pace: 10, at: start.addingTimeInterval(9.6)))
        #expect(SampleKind.isDue(last: start, pace: 10, at: start.addingTimeInterval(-60)))
    }

    @Test func everyTickWinsWhenDemandsMeet() {
        var menuBar = MonitorDemand()
        menuBar.memory = true
        menuBar.gpu = true
        menuBar.paces = [.memory: 10, .gpu: 5]
        var chart = MonitorDemand()
        chart.memory = true

        let both = menuBar.adding(chart)

        #expect(both.paces[.memory] == nil)
        #expect(both.paces[.gpu] == 5)
    }

    @Test func aSideThatDoesNotReadAMetricHasNoSay() {
        var slow = MonitorDemand()
        slow.sensors = true
        slow.paces = [.sensors: 10]
        var quicker = MonitorDemand()
        quicker.sensors = true
        quicker.paces = [.sensors: 5]

        #expect(slow.adding(MonitorDemand()).paces[.sensors] == 10)
        #expect(slow.adding(quicker).paces[.sensors] == 5)
    }
}
