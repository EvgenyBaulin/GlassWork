import Foundation
@testable import GlassWorkCore
import Testing

private final class FakeClient: FanHelperClient, @unchecked Sendable {
    // @unchecked: tests run on the main actor, one call at a time.
    private(set) var commands: [FanCommand] = []
    private(set) var heartbeats = 0
    private(set) var disconnects = 0
    var fails = false
    /// What a helper says when it no longer holds any fan.
    var holdsNothing = false
    /// Keeps the next command in flight until `release()`, as a slow helper would.
    var holdsNextSend = false
    private(set) var gate: CheckedContinuation<Void, Never>?

    func release() {
        gate?.resume()
        gate = nil
    }

    func send(_ command: FanCommand) async -> Bool {
        if holdsNextSend {
            holdsNextSend = false
            await withCheckedContinuation { gate = $0 }
        }
        commands.append(command)
        return !fails
    }

    func heartbeat() async -> Bool {
        heartbeats += 1
        return !fails && !holdsNothing
    }

    func disconnect() {
        disconnects += 1
    }
}

@MainActor
private final class FakeInstaller: FanHelperInstalling {
    var state = FanHelperState.notInstalled
    var installs = 0
    var uninstalls = 0
    var approvals = 0
    var failure: Error?
    var stateAfterInstall = FanHelperState.installed
    let client = FakeClient()
    var hasClient = true
    private(set) var onLost: (@Sendable () -> Void)?

    func install() throws {
        installs += 1
        if let failure {
            throw failure
        }
        state = stateAfterInstall
    }

    func uninstall() async throws {
        uninstalls += 1
        state = .notInstalled
    }

    func openApproval() {
        approvals += 1
    }

    func connect(onLost: @escaping @Sendable () -> Void) -> FanHelperClient? {
        self.onLost = onLost
        return hasClient ? client : nil
    }
}

private struct Failure: LocalizedError {
    var errorDescription: String? {
        "nope"
    }
}

@MainActor
struct FanControlModelTests {
    private final class Clock: @unchecked Sendable {
        // @unchecked: tests run on the main actor.
        var time: TimeInterval = 0
        var celsius: Double? = 50
    }

    private func makeStore(_ change: (inout AppSettings) -> Void = { _ in }) -> SettingsStore {
        let file = SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkFanModel-\(UUID().uuidString)/settings.json"))
        let store = SettingsStore(file: file)
        store.update(change)
        return store
    }

    private func makeModel(
        installer: FakeInstaller,
        clock: Clock = Clock(),
        store: SettingsStore? = nil
    ) -> FanControlModel {
        let store = store ?? makeStore { $0.fans.isControlEnabled = true }
        return FanControlModel(
            store: store,
            installer: installer,
            readSensors: {
                let readings = clock.celsius.map {
                    [SensorReading(key: "Tp01", group: .cpuPerformance, celsius: $0)]
                } ?? []
                return SensorSample(
                    readings: readings,
                    fans: [FanReading(id: 0, rpm: 2000, minimum: 1350, maximum: 5349)]
                )
            },
            isOnAC: { true },
            now: { clock.time }
        )
    }

    private func installed() -> FakeInstaller {
        let installer = FakeInstaller()
        installer.state = .installed
        return installer
    }

    @Test func aNewerMaxIsNeverOvertakenByAnOlderBatch() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        installer.client.holdsNextSend = true
        model.select(.custom)
        while installer.client.gate == nil {
            await Task.yield()
        }
        model.toggleMax()
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        installer.client.release()
        await model.step()
        #expect(installer.client.commands.last?.action == .max)
    }

    @Test func nothingHappensWithoutTheHelper() async {
        let installer = FakeInstaller()
        let model = makeModel(installer: installer)
        model.select(.max)
        model.toggleMax()
        await model.step()
        #expect(model.mode == .auto)
        #expect(!model.canControl)
        #expect(installer.client.commands.isEmpty)
        #expect(installer.installs == 0)
    }

    @Test func nothingHappensWithoutConsent() async {
        let installer = installed()
        let model = makeModel(installer: installer, store: makeStore())
        model.select(.max)
        await model.step()
        #expect(model.mode == .auto)
        #expect(installer.client.commands.isEmpty)
    }

    @Test func creatingTheModelInstallsAndSendsNothing() async {
        let installer = FakeInstaller()
        let model = makeModel(installer: installer)
        await model.step()
        #expect(installer.installs == 0)
        #expect(installer.onLost == nil)
        #expect(!model.isRunning)
    }

    @Test func maxReachesTheHelperAndKeepsItInformed() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        #expect(installer.client.commands == [FanCommand(fan: 0, action: .max)])
        #expect(installer.client.heartbeats >= 1)
        #expect(model.isRunning)
        model.select(.auto)
        await model.step()
        #expect(installer.client.commands.last == FanCommand(fan: 0, action: .auto))
        #expect(!model.isRunning)
    }

    @Test func aFailedCommandEndsControl() async {
        let installer = installed()
        installer.client.fails = true
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        #expect(model.mode == .auto)
        #expect(model.notice == .returnedToAuto(.helperLost))
        #expect(installer.client.disconnects == 1)
        #expect(!model.isRunning)
    }

    @Test func aBuildThatCannotConnectEndsControl() async {
        let installer = installed()
        installer.hasClient = false
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        #expect(model.mode == .auto)
        #expect(!model.isRunning)
    }

    @Test func aFailedHeartbeatEndsControl() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        installer.client.fails = true
        await model.step()
        #expect(model.mode == .auto)
        #expect(!model.isRunning)
    }

    @Test func aHelperThatLetGoEndsControl() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        installer.client.holdsNothing = true
        await model.step()
        #expect(model.mode == .auto)
        #expect(model.notice == .returnedToAuto(.helperLost))
    }

    @Test func waitingAfterWakeSurvivesAHelperHoldingNothing() async {
        let installer = installed()
        let clock = Clock()
        let model = makeModel(installer: installer, clock: clock)
        model.select(.curve)
        await model.step()
        await model.willSleep()
        clock.time = 1000
        model.didWake()
        installer.client.holdsNothing = true
        clock.time = 1005
        await model.step()
        installer.client.holdsNothing = false
        clock.time = 1010
        await model.step()
        #expect(model.mode == .curve)
    }

    @Test func failsafeIsReportedOnce() async {
        let installer = installed()
        let clock = Clock()
        let model = makeModel(installer: installer, clock: clock)
        var reports: [Double] = []
        model.onFailsafe = { reports.append($0) }
        model.select(.custom)
        await model.step()
        clock.celsius = 96
        await model.step()
        await model.step()
        #expect(reports == [96])
        #expect(model.mode == .max)
    }

    @Test func sleepSendsAutoAndStopsTheLoop() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        model.select(.max)
        await model.step()
        await model.willSleep()
        #expect(installer.client.commands.last == FanCommand(fan: 0, action: .auto))
        #expect(!model.isRunning)
    }

    @Test func aCurveComesBackTenSecondsAfterWake() async {
        let installer = installed()
        let clock = Clock()
        let model = makeModel(installer: installer, clock: clock)
        model.select(.curve)
        await model.step()
        await model.willSleep()
        clock.time = 1000
        model.didWake()
        #expect(model.isRunning)
        clock.time = 1005
        await model.step()
        #expect(model.mode == .auto)
        clock.time = 1010
        await model.step()
        #expect(model.mode == .curve)
    }

    @Test func launchModeAutoLeavesFansAlone() async {
        let installer = installed()
        let model = makeModel(installer: installer)
        model.applyLaunchMode()
        await model.step()
        #expect(model.mode == .auto)
        #expect(installer.client.commands.isEmpty)
    }

    @Test func aChosenLaunchModeApplies() {
        let installer = installed()
        let store = makeStore {
            $0.fans.isControlEnabled = true
            $0.fans.launchMode = .curve
        }
        let model = makeModel(installer: installer, store: store)
        model.applyLaunchMode()
        #expect(model.mode == .curve)
    }

    @Test func theRunningModeIsNeverSaved() async {
        let installer = installed()
        let store = makeStore { $0.fans.isControlEnabled = true }
        let model = makeModel(installer: installer, store: store)
        model.select(.max)
        await model.step()
        #expect(store.settings.fans.launchMode == .auto)
    }

    @Test func turningControlOffHandsFansBack() async {
        let installer = installed()
        let store = makeStore { $0.fans.isControlEnabled = true }
        let model = makeModel(installer: installer, store: store)
        model.select(.max)
        await model.step()
        model.setControlEnabled(false)
        await model.step()
        #expect(model.mode == .auto)
        #expect(installer.client.commands.last == FanCommand(fan: 0, action: .auto))
        #expect(!store.settings.fans.isControlEnabled)
    }

    @Test func installingEnablesControlOnceApproved() {
        let installer = FakeInstaller()
        let store = makeStore()
        let model = makeModel(installer: installer, store: store)
        model.install()
        #expect(installer.installs == 1)
        #expect(model.helperState == .installed)
        #expect(store.settings.fans.isControlEnabled)
    }

    @Test func installingWaitsForApproval() {
        let installer = FakeInstaller()
        installer.stateAfterInstall = .needsApproval
        let store = makeStore()
        let model = makeModel(installer: installer, store: store)
        model.install()
        #expect(model.helperState == .needsApproval)
        #expect(!store.settings.fans.isControlEnabled)
    }

    @Test func approvingLaterFinishesTheRequest() {
        let installer = FakeInstaller()
        installer.stateAfterInstall = .needsApproval
        let store = makeStore()
        let model = makeModel(installer: installer, store: store)
        model.install()
        installer.state = .installed
        model.refreshHelperState()
        #expect(model.canControl)
    }

    @Test func anInstalledHelperDoesNotEnableControlByItself() {
        let store = makeStore()
        let model = makeModel(installer: installed(), store: store)
        model.refreshHelperState()
        #expect(!model.canControl)
    }

    @Test func aFirstCustomHoldsTheCurrentSpeed() async {
        let installer = installed()
        let store = makeStore { $0.fans.isControlEnabled = true }
        let model = makeModel(installer: installer, store: store)
        model.select(.custom)
        await model.step()
        #expect(store.settings.fans.customRPM == 2000)
        #expect(installer.client.commands == [FanCommand(fan: 0, action: .target(2000))])
    }

    @Test func aSavedCustomTargetIsKept() async {
        let installer = installed()
        let store = makeStore {
            $0.fans.isControlEnabled = true
            $0.fans.customRPM = 3000
        }
        let model = makeModel(installer: installer, store: store)
        model.select(.custom)
        await model.step()
        #expect(store.settings.fans.customRPM == 3000)
    }

    @Test func anApprovalErrorIsNotAFailure() {
        let installer = FakeInstaller()
        installer.failure = Failure()
        installer.state = .needsApproval
        let model = makeModel(installer: installer)
        model.install()
        #expect(model.helperState == .needsApproval)
    }

    @Test func aFailedInstallIsShown() {
        let installer = FakeInstaller()
        installer.failure = Failure()
        let model = makeModel(installer: installer)
        model.install()
        #expect(model.helperState == .failed("nope"))
    }

    @Test func uninstallingReturnsToAutoFirst() async {
        let installer = installed()
        let store = makeStore { $0.fans.isControlEnabled = true }
        let model = makeModel(installer: installer, store: store)
        model.select(.max)
        await model.step()
        await model.uninstall()
        #expect(installer.client.commands.last == FanCommand(fan: 0, action: .auto))
        #expect(installer.uninstalls == 1)
        #expect(model.helperState == .notInstalled)
        #expect(!store.settings.fans.isControlEnabled)
    }

    @Test func widgetCannotStartTheFansWithoutTheService() async {
        let installer = FakeInstaller()
        let model = makeModel(installer: installer)

        model.perform(.toggleFanMax)
        model.perform(.setFanMode(.max))
        model.perform(.setFanCustom(rpm: 5000))
        await model.step()

        #expect(model.mode == .auto)
        #expect(installer.client.commands.isEmpty)
        #expect(model.settings.customRPM == 0)
        #expect(model.widgetState.control == .notInstalled)
        #expect(model.widgetState.canControl == false)
    }

    @Test func widgetCannotStartTheFansWithControlOff() async {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer, store: makeStore { $0.fans.isControlEnabled = false })

        model.perform(.toggleFanMax)
        await model.step()

        #expect(model.mode == .auto)
        #expect(model.widgetState.control == .off)
    }

    @Test func widgetMaxGoesThroughTheModel() async {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer)

        model.perform(.toggleFanMax)
        await model.step()
        #expect(model.mode == .max)
        #expect(model.widgetState.mode == .max)
        #expect(model.widgetState.canControl)

        model.perform(.toggleFanMax)
        await model.step()
        #expect(model.mode == .auto)
    }

    @Test func widgetCannotPickAPresetThatDoesNotExist() {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer)

        model.perform(.selectFanPreset("nope"))
        #expect(model.settings.selectedPresetID == FanPreset.balanced.id)

        model.perform(.selectFanPreset(FanPreset.silent.id))
        #expect(model.settings.selectedPresetID == FanPreset.silent.id)
    }

    @Test func widgetTargetSwitchesToCustomForAllFans() {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer)

        model.perform(.setFanCustom(rpm: 3000))

        #expect(model.mode == .custom)
        #expect(model.settings.customRPM == 3000)
        #expect(model.settings.customPerFan == false)
    }

    @Test(arguments: [0.0, -100, Double.infinity, Double.nan])
    func widgetIgnoresANonsenseTarget(rpm: Double) {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer)

        model.perform(.setFanCustom(rpm: rpm))

        #expect(model.mode == .auto)
    }

    @Test func otherWidgetActionsDoNothingHere() {
        let installer = FakeInstaller()
        installer.state = .installed
        let model = makeModel(installer: installer)

        model.perform(.startTimer(seconds: 60))

        #expect(model.mode == .auto)
    }
}
