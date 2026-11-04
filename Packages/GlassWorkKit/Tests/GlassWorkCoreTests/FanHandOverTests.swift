import Foundation
@testable import GlassWorkCore
import Testing

struct FanHandOverTests {
    private static let fan = FanReading(id: 0, rpm: 0, minimum: 1350, maximum: 5349)

    private var settings: FanSettings {
        var settings = FanSettings()
        settings.handsOverWhenCool = true
        settings.handOverCelsius = 45
        return settings
    }

    private func sample(_ celsius: Double, rpm: Double = 0) -> SensorSample {
        var fan = Self.fan
        fan.rpm = rpm
        return SensorSample(
            readings: [SensorReading(key: "Tp01", group: .cpuPerformance, celsius: celsius)],
            fans: [fan]
        )
    }

    private func step(
        _ engine: inout FanEngine,
        _ time: TimeInterval,
        _ celsius: Double,
        rpm: Double = 0,
        settings: FanSettings? = nil
    ) -> [FanCommand.Action] {
        let input = FanEngineInput(
            time: time,
            sample: sample(celsius, rpm: rpm),
            isOnAC: true,
            settings: settings ?? self.settings
        )
        return engine.step(input).map(\.action)
    }

    private func curveEngine() -> FanEngine {
        var engine = FanEngine()
        engine.select(.curve)
        return engine
    }

    @Test func offByDefaultSoTheMinimumStaysHeld() {
        var engine = curveEngine()
        let actions = step(&engine, 0, 35, settings: FanSettings())
        #expect(actions.count == 1)
        #expect(!engine.isWithSystem)
    }

    @Test func aCoolMacNeverTakesTheFans() {
        var engine = curveEngine()
        #expect(step(&engine, 0, 35).isEmpty)
        #expect(engine.isWithSystem)
        #expect(engine.mode == .curve)
        #expect(!engine.holdsFans)
        #expect(engine.isActive)
    }

    @Test func coolingDownGivesHeldFansBack() {
        var engine = curveEngine()
        #expect(!step(&engine, 0, 60).isEmpty)
        #expect(engine.holdsFans)
        var time = 2.0
        var actions: [FanCommand.Action] = []
        while !engine.isWithSystem, time < 400 {
            actions = step(&engine, time, 30)
            time += 2
        }
        #expect(engine.isWithSystem)
        #expect(actions == [.auto])
        #expect(!engine.holdsFans)
    }

    @Test func staysWithTheSystemInsideTheBand() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        for time in stride(from: 2.0, through: 40, by: 2) {
            let celsius = 45 + (Int(time) % 4 == 0 ? 2.5 : -2.5)
            #expect(step(&engine, time, celsius).isEmpty)
            #expect(engine.isWithSystem)
        }
    }

    @Test func comesBackAboveTheBand() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        // Five seconds of samples have to pass before the average climbs that far.
        let actions = (1 ... 6).flatMap { step(&engine, Double($0) * 2, 60) }
        #expect(!engine.isWithSystem)
        #expect(!actions.isEmpty)
        #expect(actions.allSatisfy { $0 != .auto })
    }

    @Test func aTakeBackStartsFromTheMinimumAndRamps() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        var first: Double?
        var second: Double?
        var time = 2.0
        while second == nil, time < 40 {
            for action in step(&engine, time, 90, rpm: 0) {
                guard case let .target(rpm) = action else { continue }
                if first == nil {
                    first = rpm
                } else {
                    second = rpm
                }
            }
            time += 2
        }
        #expect(first == Self.fan.minimum)
        #expect(second == Self.fan.minimum + FanSlewLimiter.maximumRate * 2)
    }

    @Test func aTakeBackHoldsBeforeLettingGoAgain() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        var time = 2.0
        while engine.isWithSystem {
            _ = step(&engine, time, 70)
            time += 2
        }
        let backAt = time - 2
        while !engine.isWithSystem, time < 500 {
            _ = step(&engine, time, 30)
            time += 2
        }
        #expect(time - 2 - backAt >= FanHandOver.minimumHold)
    }

    @Test func theFailsafeStillFiresWhileReleased() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        #expect(step(&engine, 2, 96) == [.max])
        #expect(engine.mode == .max)
        #expect(!engine.isWithSystem)
    }

    @Test func turningTheOptionOffTakesTheFansAtOnce() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        #expect(engine.isWithSystem)
        let actions = step(&engine, 2, 40, settings: FanSettings())
        #expect(!engine.isWithSystem)
        #expect(actions.count == 1)
    }

    @Test func leavingCurveClearsIt() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        engine.select(.auto)
        #expect(!engine.isWithSystem)
        #expect(step(&engine, 2, 40).isEmpty)
    }

    @Test func aWakeDecidesAfresh() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        _ = engine.willSleep()
        #expect(!engine.isWithSystem)
        engine.didWake(at: 100)
        #expect(step(&engine, 105, 40).isEmpty)
        #expect(engine.mode == .auto)
        #expect(step(&engine, 111, 40).isEmpty)
        #expect(engine.mode == .curve)
        #expect(engine.isWithSystem)
    }

    @Test func aLostSensorStillFallsBack() {
        var engine = curveEngine()
        _ = step(&engine, 0, 40)
        let input = FanEngineInput(time: 2, sample: nil, isOnAC: true, settings: settings)
        #expect(engine.step(input).isEmpty)
        #expect(engine.mode == .auto)
        #expect(engine.notice == .returnedToAuto(.sensorLost))
    }

    @Test func customIsNotAffected() {
        var engine = FanEngine()
        engine.select(.custom)
        var settings = settings
        settings.customRPM = 2000
        #expect(!step(&engine, 0, 30, settings: settings).isEmpty)
        #expect(!engine.isWithSystem)
    }

    @Test(arguments: [(10.0, 30.0), (45.0, 45.0), (200.0, 80.0)])
    func theThresholdStaysInRange(value: Double, expected: Double) {
        var settings = FanSettings()
        settings.handsOverWhenCool = true
        settings.handOverCelsius = value
        #expect(settings.handOverThreshold == expected)
    }

    @Test func offMeansNoThreshold() {
        #expect(FanSettings().handOverThreshold == nil)
    }

    @Test func aFileFromAnEarlierVersionLeavesItOff() throws {
        let settings = try JSONDecoder().decode(FanSettings.self, from: Data("{}".utf8))
        #expect(!settings.handsOverWhenCool)
        #expect(settings.handOverCelsius == 45)
    }

    @Test func survivesARoundTrip() throws {
        var settings = FanSettings()
        settings.handsOverWhenCool = true
        settings.handOverCelsius = 52
        let copy = try JSONDecoder().decode(FanSettings.self, from: JSONEncoder().encode(settings))
        #expect(copy.handsOverWhenCool)
        #expect(copy.handOverCelsius == 52)
    }
}
