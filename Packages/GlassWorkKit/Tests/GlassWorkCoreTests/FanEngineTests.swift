import Foundation
@testable import GlassWorkCore
import Testing

struct FanEngineTests {
    private static let left = FanReading(id: 0, rpm: 2000, minimum: 1350, maximum: 5349)
    private static let right = FanReading(id: 1, rpm: 2000, minimum: 1458, maximum: 5777)

    private func sample(
        cpu: Double? = 50,
        gpu: Double? = nil,
        fans: [FanReading] = [left, right]
    ) -> SensorSample {
        var readings: [SensorReading] = []
        if let cpu {
            readings.append(SensorReading(key: "Tp01", group: .cpuPerformance, celsius: cpu))
        }
        if let gpu {
            readings.append(SensorReading(key: "Tg01", group: .gpu, celsius: gpu))
        }
        return SensorSample(readings: readings, fans: fans)
    }

    private func input(
        _ time: TimeInterval,
        _ sample: SensorSample?,
        settings: FanSettings = FanSettings(),
        isOnAC: Bool = true
    ) -> FanEngineInput {
        FanEngineInput(time: time, sample: sample, isOnAC: isOnAC, settings: settings)
    }

    private func actions(_ commands: [FanCommand]) -> [FanCommand.Action] {
        commands.map(\.action)
    }

    @Test func startsInAutoAndSendsNothing() {
        var engine = FanEngine()
        #expect(engine.mode == .auto)
        #expect(!engine.isActive)
        #expect(engine.step(input(0, sample())).isEmpty)
    }

    @Test func maxCommandsEveryFanOnce() {
        var engine = FanEngine()
        engine.select(.max)
        #expect(engine.step(input(0, sample())) == [
            FanCommand(fan: 0, action: .max),
            FanCommand(fan: 1, action: .max),
        ])
        #expect(engine.step(input(2, sample())).isEmpty)
    }

    @Test func selectingAutoReleasesOnlyCommandedFans() {
        var engine = FanEngine()
        engine.select(.max)
        _ = engine.step(input(0, sample(fans: [Self.left])))
        engine.select(.auto)
        #expect(engine.step(input(2, sample())) == [FanCommand(fan: 0, action: .auto)])
        #expect(!engine.isActive)
    }

    @Test func customClampsToEachFansRange() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.customRPM = 9000
        engine.select(.custom)
        _ = engine.step(input(0, sample(), settings: settings))
        let commands = engine.step(input(100, sample(), settings: settings))
        #expect(actions(commands) == [.target(5349), .target(5777)])
    }

    @Test func customPerFanUsesEachTarget() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.customPerFan = true
        settings.customRPM = 2000
        settings.customRPMs = [3000]
        engine.select(.custom)
        // Both fans start at 2000 rpm, so the second one is already on target after the first step.
        #expect(actions(engine.step(input(0, sample(), settings: settings))) == [.target(2000), .target(2000)])
        let commands = engine.step(input(100, sample(), settings: settings))
        #expect(commands == [FanCommand(fan: 0, action: .target(3000))])
    }

    @Test func curveRampsAtTheRateLimit() {
        var engine = FanEngine()
        engine.select(.curve)
        let hot = sample(cpu: 90)
        #expect(actions(engine.step(input(0, hot))) == [.target(2000), .target(2000)])
        #expect(actions(engine.step(input(2, hot))) == [.target(2600), .target(2600)])
    }

    @Test func curveNeverGoesBelowTheFanMinimum() {
        var engine = FanEngine()
        var stopped = Self.left
        stopped.rpm = 0
        engine.select(.curve)
        let commands = engine.step(input(0, sample(cpu: 31, fans: [stopped])))
        #expect(actions(commands) == [.target(1350)])
    }

    @Test func aSteadyTargetIsNotSentAgain() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.step(input(0, sample(cpu: 60)))
        _ = engine.step(input(100, sample(cpu: 60)))
        #expect(engine.step(input(102, sample(cpu: 60))).isEmpty)
    }

    @Test func curveFollowsTheChosenSensor() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.sensor = .averageGPU
        engine.select(.curve)
        let reading = sample(cpu: 40, gpu: 90)
        _ = engine.step(input(0, reading, settings: settings))
        let commands = engine.step(input(100, reading, settings: settings))
        #expect(actions(commands) == [.target(5349), .target(5777)])
    }

    @Test func fansWithoutLimitsAreLeftAlone() {
        var engine = FanEngine()
        let broken = FanReading(id: 0, rpm: 0, minimum: 0, maximum: 0)
        engine.select(.max)
        #expect(engine.step(input(0, sample(fans: [broken]))).isEmpty)
    }

    @Test func aHeldFanThatLosesItsLimitsGoesBackToTheSystem() {
        var engine = FanEngine()
        engine.select(.custom)
        var settings = FanSettings()
        settings.customRPM = 3000
        _ = engine.step(input(0, sample(), settings: settings))
        let broken = FanReading(id: 1, rpm: 2000, minimum: 0, maximum: 0)
        let commands = engine.step(input(2, sample(fans: [Self.left, broken]), settings: settings))
        #expect(commands.contains(FanCommand(fan: 1, action: .auto)))
    }

    @Test func theFailsafeStillRaisesAHeldFanWithoutLimits() {
        var engine = FanEngine()
        engine.select(.custom)
        var settings = FanSettings()
        settings.customRPM = 3000
        _ = engine.step(input(0, sample(), settings: settings))
        let broken = FanReading(id: 1, rpm: 2000, minimum: 0, maximum: 0)
        let commands = engine.step(input(2, sample(cpu: 96, fans: [Self.left, broken]), settings: settings))
        #expect(commands.contains(FanCommand(fan: 1, action: .max)))
    }

    // MARK: Failsafe

    @Test(arguments: [FanMode.curve, .custom])
    func failsafeForcesMax(mode: FanMode) {
        var engine = FanEngine()
        engine.select(mode)
        _ = engine.step(input(0, sample()))
        let commands = engine.step(input(2, sample(cpu: 96)))
        #expect(engine.mode == .max)
        #expect(actions(commands) == [.max, .max])
        #expect(engine.notice == .failsafeMax(celsius: 96, previous: mode))
    }

    @Test func exactlyNinetyFiveDoesNotTrigger() {
        var engine = FanEngine()
        engine.select(.custom)
        _ = engine.step(input(0, sample(cpu: 95)))
        #expect(engine.mode == .custom)
    }

    @Test func failsafeWatchesCPUEvenWhenTheCurveUsesAnotherSensor() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.sensor = .averageGPU
        engine.select(.curve)
        _ = engine.step(input(0, sample(cpu: 97, gpu: 40), settings: settings))
        #expect(engine.mode == .max)
    }

    @Test func failsafeSkipsTheRateLimit() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.step(input(0, sample()))
        #expect(actions(engine.step(input(0.1, sample(cpu: 99)))) == [.max, .max])
    }

    @Test func failsafeStaysOnUntilTheUserPicksAMode() {
        var engine = FanEngine()
        engine.select(.custom)
        _ = engine.step(input(0, sample(cpu: 96)))
        #expect(engine.step(input(2, sample(cpu: 40))).isEmpty)
        #expect(engine.mode == .max)
        engine.select(.custom)
        #expect(engine.mode == .custom)
        #expect(engine.notice == nil)
    }

    @Test func failsafeReturnsIfStillHotAfterTheUserPicksAMode() {
        var engine = FanEngine()
        engine.select(.custom)
        _ = engine.step(input(0, sample(cpu: 96)))
        engine.select(.custom)
        _ = engine.step(input(2, sample(cpu: 96)))
        #expect(engine.mode == .max)
    }

    @Test func userChosenMaxShowsNoFailsafe() {
        var engine = FanEngine()
        engine.select(.max)
        _ = engine.step(input(0, sample(cpu: 99)))
        #expect(engine.notice == nil)
    }

    @Test func losingTheCPUReadingReturnsToAuto() {
        var engine = FanEngine()
        engine.select(.custom)
        _ = engine.step(input(0, sample()))
        let commands = engine.step(input(2, sample(cpu: nil)))
        #expect(engine.mode == .auto)
        #expect(actions(commands) == [.auto, .auto])
        #expect(engine.notice == .returnedToAuto(.sensorLost))
    }

    @Test func noSampleAtAllReturnsToAuto() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.step(input(0, sample()))
        #expect(actions(engine.step(input(2, nil))) == [.auto, .auto])
    }

    @Test func losingTheCurveSensorReturnsToAuto() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.sensor = .sensor("Tx99")
        engine.select(.curve)
        _ = engine.step(input(0, sample(), settings: settings))
        #expect(engine.mode == .auto)
        #expect(engine.notice == .returnedToAuto(.sensorLost))
    }

    // MARK: Max button

    @Test func maxButtonReturnsToThePreviousMode() {
        var engine = FanEngine()
        engine.select(.curve)
        engine.toggleMax()
        #expect(engine.mode == .max)
        engine.toggleMax()
        #expect(engine.mode == .curve)
    }

    @Test func maxButtonFromAutoReturnsToAuto() {
        var engine = FanEngine()
        engine.toggleMax()
        engine.toggleMax()
        #expect(engine.mode == .auto)
    }

    @Test func maxButtonAfterFailsafeReturnsToTheInterruptedMode() {
        var engine = FanEngine()
        engine.select(.custom)
        _ = engine.step(input(0, sample(cpu: 96)))
        engine.toggleMax()
        #expect(engine.mode == .custom)
    }

    // MARK: Sleep and helper loss

    @Test func sleepReleasesFansAndOnlyACurveComesBack() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.step(input(0, sample()))
        #expect(actions(engine.willSleep()) == [.auto, .auto])
        #expect(engine.mode == .auto)
        engine.didWake(at: 100)
        #expect(engine.resumeTime == 110)
        #expect(engine.step(input(105, sample())).isEmpty)
        #expect(engine.mode == .auto)
        #expect(!engine.step(input(110, sample())).isEmpty)
        #expect(engine.mode == .curve)
    }

    @Test(arguments: [FanMode.max, .custom])
    func sleepEndsManualModesForGood(mode: FanMode) {
        var engine = FanEngine()
        engine.select(mode)
        _ = engine.step(input(0, sample()))
        _ = engine.willSleep()
        engine.didWake(at: 100)
        #expect(engine.resumeTime == nil)
        #expect(engine.notice == .returnedToAuto(.sleep))
        _ = engine.step(input(200, sample()))
        #expect(engine.mode == .auto)
    }

    @Test func sleepInAutoChangesNothing() {
        var engine = FanEngine()
        #expect(engine.willSleep().isEmpty)
        engine.didWake(at: 100)
        #expect(engine.resumeTime == nil)
        #expect(engine.notice == nil)
    }

    @Test func aChoiceDuringTheWakeDelayCancelsTheResume() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.willSleep()
        engine.didWake(at: 100)
        engine.select(.auto)
        _ = engine.step(input(120, sample()))
        #expect(engine.mode == .auto)
    }

    @Test func curveRestartsFromCurrentSpeedAfterWake() {
        var engine = FanEngine()
        engine.select(.curve)
        _ = engine.step(input(0, sample(cpu: 90)))
        _ = engine.step(input(2, sample(cpu: 90)))
        _ = engine.willSleep()
        engine.didWake(at: 1000)
        let commands = engine.step(input(1010, sample(cpu: 90)))
        #expect(actions(commands) == [.target(2000), .target(2000)])
    }

    @Test func losingTheHelperEndsControlWithoutCommands() {
        var engine = FanEngine()
        engine.select(.max)
        _ = engine.step(input(0, sample()))
        engine.helperLost()
        #expect(engine.mode == .auto)
        #expect(!engine.isActive)
        #expect(engine.notice == .returnedToAuto(.helperLost))
        #expect(engine.step(input(2, sample())).isEmpty)
    }

    // MARK: Power rules

    @Test func powerRulesPickTheCurveBySource() {
        var settings = FanSettings()
        settings.powerRules.isEnabled = true
        settings.powerRules.adapterPresetID = FanPreset.performance.id
        settings.powerRules.batteryPresetID = FanPreset.silent.id
        #expect(settings.curve(forFan: 0, isOnAC: true) == FanPreset.performance.curve)
        #expect(settings.curve(forFan: 0, isOnAC: false) == FanPreset.silent.curve)
    }

    @Test func powerRulesAreOffByDefault() {
        let settings = FanSettings()
        #expect(settings.curve(forFan: 0, isOnAC: false) == FanPreset.balanced.curve)
    }

    @Test func powerRulesWinOverSeparateCurves() {
        var settings = FanSettings()
        settings.separateCurves = true
        settings.fanPresetIDs = [FanPreset.silent.id, FanPreset.performance.id]
        #expect(settings.curve(forFan: 1, isOnAC: true) == FanPreset.performance.curve)
        settings.powerRules.isEnabled = true
        #expect(settings.curve(forFan: 1, isOnAC: true) == FanPreset.balanced.curve)
    }

    @Test func aFanOnTheSelectedPresetFollowsItsDraft() {
        var settings = FanSettings()
        settings.separateCurves = true
        settings.fanPresetIDs = [FanPreset.balanced.id, FanPreset.silent.id]
        let edited = FanPreset.balanced.curve.moving(2, to: .init(celsius: 62, percent: 52))
        settings.applyEdit(edited)
        #expect(settings.curve(forFan: 0, isOnAC: true) == edited)
        #expect(settings.curve(forFan: 1, isOnAC: true) == FanPreset.silent.curve)
    }

    @Test func engineUsesTheBatteryCurveOnBattery() {
        var engine = FanEngine()
        var settings = FanSettings()
        settings.powerRules.isEnabled = true
        engine.select(.curve)
        let reading = sample(cpu: 60)
        _ = engine.step(input(0, reading, settings: settings, isOnAC: false))
        let commands = engine.step(input(100, reading, settings: settings, isOnAC: false))
        let silent = FanPreset.silent.curve.rpm(at: 60, in: 1350 ... 5349).rounded()
        #expect(commands.first?.action == .target(silent))
    }
}

struct FanSettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.fans.launchMode = .curve
        settings.fans.sensor = .sensor("Tp01")
        settings.fans.saveCurve(as: "Quiet Studio", id: "quiet")
        settings.fans.powerRules.isEnabled = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func oldFilesGetDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.fans == FanSettings())
        #expect(settings.fans.launchMode == .auto)
        #expect(!settings.fans.isControlEnabled)
    }

    @Test func aBadFanFieldKeepsTheRest() throws {
        let json = #"{"numberStyle":"precise","fans":{"sensor":"nonsense","launchMode":"warp","customRPM":3000}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.numberStyle == .precise)
        #expect(settings.fans.sensor == .averageCPU)
        #expect(settings.fans.launchMode == .auto)
        #expect(settings.fans.customRPM == 3000)
    }

    @Test func aBrokenFanSectionKeepsTheFile() throws {
        let settings = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"numberStyle":"precise","fans":[1,2]}"#.utf8)
        )
        #expect(settings.numberStyle == .precise)
        #expect(settings.fans == FanSettings())
    }

    @Test func aClearedDraftStaysClearedThroughTheFile() throws {
        let file = SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkFans-\(UUID().uuidString)/settings.json"))
        var settings = AppSettings()
        settings.fans.applyEdit(FanPreset.silent.curve)
        try file.save(settings)
        #expect(try file.load()?.fans.hasDraft == true)

        settings.fans.selectPreset(FanPreset.balanced.id)
        try file.save(settings)

        #expect(try file.load()?.fans.hasDraft == false)
    }

    @Test func sensorChoicesSurviveAsStrings() {
        for choice in [SensorChoice.averageCPU, .hottestCPU, .averageGPU, .averageSoC, .sensor("Tp0a")] {
            #expect(SensorChoice(rawValue: choice.rawValue) == choice)
        }
        #expect(SensorChoice(rawValue: "sensor:") == nil)
        #expect(SensorChoice(rawValue: "") == nil)
    }

    @Test func editingABuiltInKeepsADraft() {
        var settings = FanSettings()
        let edited = FanPreset.balanced.curve.moving(2, to: .init(celsius: 62, percent: 52))
        settings.applyEdit(edited)
        #expect(settings.hasDraft)
        #expect(settings.selectedCurve == edited)
        #expect(settings.selectedPreset == .balanced)
    }

    @Test func editingBackToTheOriginalDropsTheDraft() {
        var settings = FanSettings()
        settings.applyEdit(FanPreset.silent.curve)
        settings.applyEdit(FanPreset.balanced.curve)
        #expect(!settings.hasDraft)
    }

    @Test func editingAUserPresetChangesItInPlace() {
        var settings = FanSettings()
        settings.saveCurve(as: "Mine", id: "mine")
        settings.applyEdit(FanPreset.silent.curve)
        #expect(!settings.hasDraft)
        #expect(settings.preset("mine").curve == FanPreset.silent.curve)
    }

    @Test func saveAsTurnsADraftIntoAPreset() {
        var settings = FanSettings()
        settings.applyEdit(FanPreset.silent.curve)
        settings.saveCurve(as: "Mine", id: "mine")
        #expect(!settings.hasDraft)
        #expect(settings.selectedPresetID == "mine")
        #expect(settings.selectedCurve == FanPreset.silent.curve)
    }

    @Test func deletingAPresetMovesItsUsersToBalanced() {
        var settings = FanSettings()
        settings.saveCurve(as: "Mine", id: "mine")
        settings.fanPresetIDs = ["mine", "silent"]
        settings.powerRules.adapterPresetID = "mine"
        settings.powerRules.batteryPresetID = "mine"

        settings.deletePreset("mine")

        #expect(settings.userPresets.isEmpty)
        #expect(settings.selectedPresetID == "balanced")
        #expect(settings.fanPresetIDs == ["balanced", "silent"])
        #expect(settings.powerRules.adapterPresetID == "balanced")
        #expect(settings.powerRules.batteryPresetID == "balanced")
    }

    @Test func renamingKeepsTheCurve() {
        var settings = FanSettings()
        settings.saveCurve(as: "Mine", id: "mine")
        settings.renamePreset("mine", to: "Quiet")
        #expect(settings.preset("mine").name == "Quiet")
        #expect(settings.preset("mine").curve == FanPreset.balanced.curve)
    }

    @Test func builtInPresetsCannotBeRenamed() {
        var settings = FanSettings()
        settings.renamePreset("balanced", to: "Loud")
        #expect(settings.preset("balanced").name == "Balanced")
    }

    @Test func builtInPresetsCannotBeDeleted() {
        var settings = FanSettings()
        settings.deletePreset("balanced")
        #expect(settings.presets.count == 3)
    }

    @Test func aMissingPresetFallsBackToBalanced() {
        var settings = FanSettings()
        settings.selectedPresetID = "gone"
        #expect(settings.selectedCurve == FanPreset.balanced.curve)
    }
}
