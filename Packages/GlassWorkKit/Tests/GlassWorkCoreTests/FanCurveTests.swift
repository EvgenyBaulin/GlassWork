import Foundation
@testable import GlassWorkCore
import Testing

struct FanCurveTests {
    private typealias Point = FanCurve.Point

    private let balanced = FanPreset.balanced.curve

    @Test func interpolatesBetweenPoints() {
        #expect(balanced.percent(at: 60) == 44)
        #expect(balanced.percent(at: 37.5) == 7.5)
        #expect(abs(balanced.percent(at: 62) - 47.466) < 0.01)
    }

    @Test func isFlatOutsideItsPoints() {
        #expect(balanced.percent(at: 10) == 0)
        #expect(balanced.percent(at: 99) == 100)
    }

    @Test func mapsPercentToEachFansOwnRange() {
        // The two fans of this Mac, as the SMC reports them.
        #expect(balanced.rpm(at: 30, in: 1350 ... 5349) == 1350)
        #expect(balanced.rpm(at: 90, in: 1458 ... 5777) == 5777)
        #expect(FanCurve.rpm(percent: 50, in: 1000 ... 2000) == 1500)
        #expect(FanCurve.rpm(percent: 900, in: 1000 ... 2000) == 2000)
        #expect(FanCurve.rpm(percent: -5, in: 1000 ... 2000) == 1000)
    }

    @Test func sortsAndRepairsPoints() {
        let curve = FanCurve(points: [
            Point(celsius: 80, percent: 40),
            Point(celsius: 40, percent: 60),
            Point(celsius: 60, percent: 10),
        ])
        #expect(curve.points == [
            Point(celsius: 40, percent: 60),
            Point(celsius: 60, percent: 60),
            Point(celsius: 80, percent: 60),
        ])
    }

    @Test func dropsPointsCloserThanTheMinimumGap() {
        let curve = FanCurve(points: [
            Point(celsius: 40, percent: 10),
            Point(celsius: 40.5, percent: 20),
            Point(celsius: 41, percent: 30),
        ])
        #expect(curve.points.map(\.celsius) == [40, 41])
    }

    @Test func clampsWildValues() {
        let curve = FanCurve(points: [
            Point(celsius: -40, percent: -10),
            Point(celsius: 500, percent: 900),
            Point(celsius: .nan, percent: 50),
            Point(celsius: 60, percent: .infinity),
        ])
        #expect(curve.points == [Point(celsius: 30, percent: 0), Point(celsius: 100, percent: 100)])
    }

    @Test func keepsAtMostEightPoints() {
        let curve = FanCurve(points: (0 ..< 12).map { Point(celsius: 30 + Double($0) * 5, percent: Double($0) * 5) })
        #expect(curve.points.count == 8)
    }

    @Test func tooFewPointsFallBackToBalanced() {
        #expect(FanCurve(points: []) == balanced)
        #expect(FanCurve(points: [Point(celsius: 50, percent: 50)]) == balanced)
    }

    @Test func aDraggedPointStopsAtItsNeighbours() {
        let moved = balanced.moving(1, to: Point(celsius: 70, percent: 90))
        #expect(moved.points[1] == Point(celsius: 59, percent: 44))
        let down = balanced.moving(1, to: Point(celsius: 10, percent: -5))
        #expect(down.points[1] == Point(celsius: 31, percent: 0))
    }

    @Test func endPointsStopAtTheChartEdges() {
        #expect(balanced.moving(0, to: Point(celsius: 0, percent: 0)).points[0].celsius == 30)
        #expect(balanced.moving(4, to: Point(celsius: 120, percent: 120)).points[4]
            == Point(celsius: 100, percent: 100))
    }

    @Test func movingIgnoresBadInput() {
        #expect(balanced.moving(9, to: Point(celsius: 50, percent: 50)) == balanced)
        #expect(balanced.moving(1, to: Point(celsius: .nan, percent: 50)) == balanced)
    }

    @Test func insertsInOrderWithinItsNeighbours() throws {
        let curve = try #require(balanced.inserting(Point(celsius: 52, percent: 90)))
        #expect(curve.points.count == 6)
        #expect(curve.points[2] == Point(celsius: 52, percent: 44))
    }

    @Test func refusesAPointWithoutRoom() {
        #expect(balanced.inserting(Point(celsius: 45.5, percent: 20)) == nil)
        #expect(balanced.inserting(Point(celsius: 20, percent: 20)) == nil)
        let full = FanCurve(points: (0 ..< 8).map { Point(celsius: 30 + Double($0) * 5, percent: Double($0) * 5) })
        #expect(full.inserting(Point(celsius: 90, percent: 90)) == nil)
    }

    @Test func removesDownToTwoPoints() throws {
        var curve = balanced
        for _ in 0 ..< 3 {
            curve = try #require(curve.removing(1))
        }
        #expect(curve.points.count == 2)
        #expect(curve.removing(0) == nil)
    }

    @Test func decodingRepairsAHandEdit() throws {
        let json = #"[{"celsius":70,"percent":20},{"celsius":40,"percent":80}]"#
        let curve = try JSONDecoder().decode(FanCurve.self, from: Data(json.utf8))
        #expect(curve.points == [Point(celsius: 40, percent: 80), Point(celsius: 70, percent: 80)])
    }

    @Test func builtInCurvesAreOrderedAndFullBeforeTheFailsafe() {
        for celsius in stride(from: 30.0, through: 100, by: 1) {
            let silent = FanPreset.silent.curve.percent(at: celsius)
            let middle = FanPreset.balanced.curve.percent(at: celsius)
            let performance = FanPreset.performance.curve.percent(at: celsius)
            #expect(silent <= middle)
            #expect(middle <= performance)
        }
        for preset in FanPreset.builtIn {
            #expect(preset.curve.percent(at: FanEngine.failsafeCelsius) == 100)
            #expect(preset.isBuiltIn)
        }
    }

    @Test func balancedMatchesTheSpecExample() {
        // 1200–5800 rpm is the sample range the design uses for "62 °C → 3400 rpm".
        let rpm = balanced.rpm(at: 62, in: 1200 ... 5800)
        #expect(abs(rpm - 3400) < 25)
    }
}

struct FanSmoothingTests {
    @Test func averagesOverTimeNotSampleCount() {
        var filter = FanTemperatureFilter()
        #expect(filter.filtered(50, at: 0) == 50)
        #expect(filter.filtered(60, at: 2) == 55)
        #expect(filter.filtered(70, at: 4) == 60)
        // The reading from t=0 is now older than five seconds.
        #expect(filter.filtered(70, at: 6) == 200.0 / 3)
    }

    @Test func heatingIsFollowedAtOnce() {
        var filter = FanTemperatureFilter()
        _ = filter.filtered(50, at: 0)
        #expect(filter.filtered(50.5, at: 10) == 50.5)
    }

    @Test func coolingWaitsForTheHysteresis() {
        var filter = FanTemperatureFilter()
        _ = filter.filtered(60, at: 0)
        #expect(filter.filtered(58, at: 10) == 60)
        #expect(filter.filtered(57, at: 20) == 60)
        #expect(filter.filtered(56, at: 30) == 59)
        #expect(filter.filtered(50, at: 40) == 53)
    }

    @Test func smallSwingsDoNotMoveTheValue() {
        var filter = FanTemperatureFilter()
        _ = filter.filtered(60, at: 0)
        for (index, value) in [59.0, 58, 59.5, 58.5, 59].enumerated() {
            #expect(filter.filtered(value, at: Double(index + 1) * 10) == 60)
        }
    }

    @Test func resetForgetsEverything() {
        var filter = FanTemperatureFilter()
        _ = filter.filtered(90, at: 0)
        filter.reset()
        #expect(filter.filtered(40, at: 1) == 40)
    }

    @Test func limitsTheRateByRealElapsedTime() {
        var limiter = FanSlewLimiter()
        #expect(limiter.limited([0: 5000], starts: [0: 2000], at: 0) == [0: 2000])
        #expect(limiter.limited([0: 5000], starts: [0: 2000], at: 2) == [0: 2600])
        #expect(limiter.limited([0: 5000], starts: [0: 2000], at: 2.5) == [0: 2750])
        #expect(limiter.limited([0: 1000], starts: [0: 2000], at: 3.5) == [0: 2450])
    }

    @Test func aLongGapAllowsALongStep() {
        var limiter = FanSlewLimiter()
        _ = limiter.limited([0: 5000], starts: [0: 2000], at: 0)
        #expect(limiter.limited([0: 5000], starts: [0: 2000], at: 60) == [0: 5000])
    }

    @Test func stopsExactlyOnTheTarget() {
        var limiter = FanSlewLimiter()
        _ = limiter.limited([0: 2100], starts: [0: 2000], at: 0)
        #expect(limiter.limited([0: 2100], starts: [0: 2000], at: 10) == [0: 2100])
    }

    @Test func eachFanIsLimitedOnItsOwn() {
        var limiter = FanSlewLimiter()
        _ = limiter.limited([0: 5000, 1: 1000], starts: [0: 2000, 1: 3000], at: 0)
        #expect(limiter.limited([0: 5000, 1: 1000], starts: [:], at: 1) == [0: 2300, 1: 2700])
    }
}
