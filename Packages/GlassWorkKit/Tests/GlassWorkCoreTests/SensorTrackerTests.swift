import Foundation
@testable import GlassWorkCore
import Testing

struct SensorTrackerTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    private func reading(_ key: String, _ group: SensorGroup, _ celsius: Double) -> SensorReading {
        SensorReading(key: key, group: group, celsius: celsius)
    }

    private func sample(_ readings: [SensorReading]) -> SensorSample {
        SensorSample(readings: readings, fans: [])
    }

    @Test func extremesCoverMoreThanTheKeptPoints() {
        var tracker = SensorTracker()
        let all = Set(SensorGroup.allCases)
        tracker.apply(sample([reading("Tp01", .cpuPerformance, 20)]), groups: all, at: start)
        for index in 1 ... SensorTracker.capacity + 20 {
            tracker.apply(
                sample([reading("Tp01", .cpuPerformance, 50 + Double(index % 3))]),
                groups: all,
                at: start.addingTimeInterval(Double(index))
            )
        }
        let track = tracker.track(for: "Tp01")
        #expect(track?.points.count == SensorTracker.capacity)
        #expect(track?.minimum == 20)
        #expect(track?.maximum == 52)
    }

    @Test func onlyListedGroupsAreTracked() {
        var tracker = SensorTracker()
        let readings = sample([reading("Tp01", .cpuPerformance, 50), reading("Tg01", .gpu, 40)])
        tracker.apply(readings, groups: [.cpuPerformance], at: start)
        #expect(tracker.track(for: "Tp01") != nil)
        #expect(tracker.track(for: "Tg01") == nil)
    }

    @Test func hidingAGroupDropsItsHistory() {
        var tracker = SensorTracker()
        let readings = sample([reading("Tp01", .cpuPerformance, 50), reading("Tg01", .gpu, 40)])
        tracker.apply(readings, groups: [.cpuPerformance, .gpu], at: start)
        tracker.apply(readings, groups: [.cpuPerformance], at: start.addingTimeInterval(5))
        #expect(tracker.track(for: "Tg01") == nil)
        #expect(tracker.track(for: "Tp01")?.points.count == 2)
    }

    @Test func aSensorMissingFromOneSampleKeepsItsHistory() {
        var tracker = SensorTracker()
        let all = Set(SensorGroup.allCases)
        tracker.apply(sample([reading("Tp01", .cpuPerformance, 50)]), groups: all, at: start)
        tracker.apply(sample([]), groups: all, at: start.addingTimeInterval(5))
        #expect(tracker.track(for: "Tp01")?.points.count == 1)
    }
}
