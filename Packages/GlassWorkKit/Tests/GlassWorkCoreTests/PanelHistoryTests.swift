import Foundation
@testable import GlassWorkCore
import Testing

private let start = Date(timeIntervalSince1970: 1_800_000_000 / 600 * 600)

private func point(_ seconds: Double, _ value: Double) -> History<Double>.Point {
    .init(date: start.addingTimeInterval(seconds), value: value)
}

struct RangeStatsTests {
    @Test func summarizesMinimumAverageAndMaximum() throws {
        let stats = try #require(RangeStats([point(0, 0.2), point(2, 0.6), point(4, 0.1), point(6, 0.5)]))
        #expect(stats.minimum == 0.1)
        #expect(stats.maximum == 0.6)
        #expect(abs(stats.average - 0.35) < 1e-9)
    }

    @Test func nothingToSummarize() {
        #expect(RangeStats([]) == nil)
    }
}

struct TieredHistoryRangeTests {
    private func filled(seconds: Int) -> TieredHistory {
        var history = TieredHistory()
        for second in 0 ... seconds {
            history.append(Double(second), at: start.addingTimeInterval(Double(second)))
        }
        return history
    }

    @Test func remembersWhenTheFirstValueArrived() {
        #expect(TieredHistory().firstDate == nil)
        #expect(filled(seconds: 5).firstDate == start)
    }

    @Test func aRangeLongerThanTheRunReachesBeforeStart() {
        let history = filled(seconds: 600)
        let now = start.addingTimeInterval(600)
        #expect(!history.reachesBeforeStart(.minute, now: now))
        #expect(history.reachesBeforeStart(.hour, now: now))
        #expect(history.reachesBeforeStart(.day, now: now))
    }

    @Test func aRangeThatJustFitsDoesNotReachBeforeStart() {
        let history = filled(seconds: 60)
        #expect(!history.reachesBeforeStart(.minute, now: start.addingTimeInterval(60)))
        #expect(history.reachesBeforeStart(.minute, now: start.addingTimeInterval(59)))
    }

    @Test func noValuesMeansNothingToMark() {
        #expect(!TieredHistory().reachesBeforeStart(.day))
    }

    @Test func aMinuteGraphKeepsTheNewestThirtyValues() {
        let history = filled(seconds: 120)
        let values = history.graph(span: 60, maxPoints: 30, now: start.addingTimeInterval(120))
        #expect(values.count == 30)
        #expect(values.last == 120)
    }

    @Test func aLongerGraphReadsTheTenSecondTierAndThinsIt() throws {
        let history = filled(seconds: 900)
        let now = start.addingTimeInterval(900)
        let five = history.graph(span: 300, maxPoints: 30, now: now)
        let fifteen = history.graph(span: 900, maxPoints: 30, now: now)
        #expect((28 ... 30).contains(five.count))
        #expect(fifteen.count <= 30)
        #expect(fifteen.count > 25)
        // Values rise with time, so a wider span starts lower.
        let widerStart = try #require(fifteen.first)
        let narrowerStart = try #require(five.first)
        #expect(widerStart < narrowerStart)
        #expect(fifteen == fifteen.sorted())
    }

    @Test func thinningAveragesNeighbours() {
        let thinned = TieredHistory.thinned([1, 3, 5, 7, 9, 11], to: 3)
        #expect(thinned == [2, 6, 10])
        #expect(TieredHistory.thinned([1, 2], to: 3) == [1, 2])
    }

    @Test func theGraphSpanOptionKnowsOnlyThreeSpans() {
        #expect([String: String]().graphSpan == 60)
        #expect([ItemOption.graphMinutes: "5"].graphSpan == 300)
        #expect([ItemOption.graphMinutes: "15"].graphSpan == 900)
        #expect([ItemOption.graphMinutes: "7"].graphSpan == 60)
        #expect([ItemOption.graphMinutes: "x"].graphSpan == 60)
    }
}

struct TemperatureZoneTests {
    @Test func zonesStartAtTheirThresholds() {
        #expect(TemperatureZone(celsius: 20) == .cool)
        #expect(TemperatureZone(celsius: 59.9) == .cool)
        #expect(TemperatureZone(celsius: 60) == .warm)
        #expect(TemperatureZone(celsius: 79.9) == .warm)
        #expect(TemperatureZone(celsius: 80) == .hot)
        #expect(TemperatureZone(celsius: 104) == .hot)
    }
}

struct PingJitterTests {
    private func log(_ values: [Double?]) -> PingLog {
        var log = PingLog()
        for (index, value) in values.enumerated() {
            log.append(
                value.map { .reply(milliseconds: $0) } ?? .timeout,
                at: start.addingTimeInterval(Double(index) * 30)
            )
        }
        return log
    }

    @Test func eachSampleGetsTheJitterOfItsWindow() {
        let jitter = log([10, 20, 20, 50]).rollingJitter.map(\.value)
        #expect(jitter == [0, 10, 5, 40.0 / 3])
    }

    @Test func aMissedEchoLeavesTheWindowAsItWas() {
        let jitter = log([10, nil, 30]).rollingJitter.map(\.value)
        #expect(jitter == [0, 0, 20])
    }

    @Test func onlyTheLastWindowCounts() {
        var values: [Double?] = [1000]
        values += Array(repeating: 10, count: PingLog.jitterWindow)
        let jitter = log(values).rollingJitter.map(\.value)
        #expect(jitter.last == 0)
    }

    @Test func theSummaryStillUsesEveryReply() throws {
        let stats = try #require(log([10, 20, 20, 50]).stats)
        #expect(abs(stats.jitter - 40.0 / 3) < 1e-9)
    }
}

struct RateDayChangeTests {
    private func quote(_ points: [(TimeInterval, Double)]) -> RateQuote {
        RateQuote(
            pair: RatePair(base: "USD", quote: "EUR"),
            source: .frankfurter,
            value: points.last?.1 ?? 0,
            change: 0,
            history: points.map { RatePoint(date: start.addingTimeInterval($0.0), value: $0.1) },
            date: start
        )
    }

    private let day: TimeInterval = 86400

    @Test func eachDayIsComparedWithTheOneBefore() {
        let changes = quote([(0, 100), (day, 110), (2 * day, 99)]).dayChanges
        #expect(changes[0].value.isNaN)
        #expect(abs(changes[1].value - 0.1) < 1e-9)
        #expect(abs(changes[2].value - -0.1) < 1e-9)
    }

    @Test func aWeekendIsSkipped() {
        let changes = quote([(0, 100), (3 * day, 103)]).dayChanges
        #expect(abs(changes[1].value - 0.03) < 1e-9)
    }

    @Test func severalPointsInADayCompareWithTheLastOneADayBack() {
        let hour: TimeInterval = 3600
        let changes = quote([(0, 100), (12 * hour, 105), (25 * hour, 110)]).dayChanges
        #expect(changes[1].value.isNaN)
        #expect(abs(changes[2].value - 0.1) < 1e-9)
    }
}

struct BusiestAppTests {
    private func app(_ id: String, cpu: Double) -> AppUsage {
        AppUsage(id: id, pid: 1, name: id, cpu: cpu, memory: 1_000_000)
    }

    private func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    private var history: AppUsageHistory {
        var history = AppUsageHistory()
        for minute in 0 ... 5 {
            let busy = minute < 3 ? "com.example.editor" : "com.example.browser"
            history.record([app(busy, cpu: 80), app("com.example.quiet", cpu: 2)], at: minutes(Double(minute)))
        }
        return history
    }

    @Test func theBusiestAppOfEachMinute() throws {
        let early = try #require(history.busiest(at: minutes(1)))
        #expect(early.id == "com.example.editor")
        #expect(early.cpu == 80)
        #expect(history.busiest(at: minutes(4))?.id == "com.example.browser")
    }

    @Test func aMomentBetweenMinutesTakesTheNearest() {
        #expect(history.busiest(at: minutes(1).addingTimeInterval(20))?.id == "com.example.editor")
        #expect(history.busiest(at: minutes(3).addingTimeInterval(-20))?.id == "com.example.browser")
    }

    @Test func noRecordNearbyMeansNoAnswer() {
        #expect(history.busiest(at: minutes(-30)) == nil)
        #expect(AppUsageHistory().busiest(at: start) == nil)
    }
}
