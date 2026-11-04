import Foundation
@testable import GlassWorkCore
import Testing

/// Stands in for the SMC. Key types and sizes are the ones this hardware really reports.
final class FakeSMC: FanSMCAccess, @unchecked Sendable {
    // @unchecked: tests touch it from one queue at a time, guarded by `lock` where XPC is involved.
    private let lock = NSLock()
    private var values: [String: SMCClient.Value]
    private(set) var writes: [(key: String, bytes: [UInt8])] = []
    /// Number of writes of a key that fail before one succeeds.
    var refusals: [String: Int] = [:]

    init(fans: Int = 2, mode: UInt8 = 3, modeKey: String = "Md", hasTestKey: Bool = true) {
        var values: [String: SMCClient.Value] = ["FNum": .init(type: "ui8 ", bytes: [UInt8(fans)])]
        if hasTestKey {
            values["Ftst"] = .init(type: "ui8 ", bytes: [0])
        }
        for fan in 0 ..< fans {
            values["F\(fan)\(modeKey)"] = .init(type: "ui8 ", bytes: [mode])
            values["F\(fan)Tg"] = .init(type: "flt ", bytes: [0, 0, 0, 0])
            values["F\(fan)Mn"] = .init(type: "flt ", bytes: [0, 192, 168, 68])
            values["F\(fan)Mx"] = .init(type: "flt ", bytes: [0, 40, 167, 69])
        }
        self.values = values
    }

    func read(_ key: String) -> SMCClient.Value? {
        lock.withLock { values[key] }
    }

    func write(_ key: String, bytes: [UInt8]) -> Bool {
        lock.withLock {
            if let left = refusals[key], left > 0 {
                refusals[key] = left - 1
                return false
            }
            writes.append((key, bytes))
            if let old = values[key] {
                values[key] = .init(type: old.type, bytes: bytes)
            }
            return true
        }
    }

    func set(_ key: String, _ value: SMCClient.Value?) {
        lock.withLock { values[key] = value }
    }

    func number(_ key: String) -> Double? {
        read(key)?.number
    }

    var writtenKeys: [String] {
        lock.withLock { writes.map(\.key) }
    }
}

struct SMCValueTests {
    @Test func encodesFloatsAsThisMacStoresThem() {
        let key = SMCClient.Value(type: "flt ", bytes: [0, 0, 0, 0])
        #expect(key.encoded(1350) == [0, 192, 168, 68])
        #expect(key.encoded(5349) == [0, 40, 167, 69])
    }

    @Test func encodedFloatsReadBack() throws {
        let key = SMCClient.Value(type: "flt ", bytes: [0, 0, 0, 0])
        let bytes = try #require(key.encoded(3400))
        #expect(SMCClient.Value(type: "flt ", bytes: bytes).number == 3400)
    }

    @Test func encodesIntegersBigEndian() {
        #expect(SMCClient.Value(type: "ui8 ", bytes: [3]).encoded(1) == [1])
        #expect(SMCClient.Value(type: "ui16", bytes: [0, 0]).encoded(258) == [1, 2])
    }

    @Test func refusesWhatAKeyCannotHold() {
        #expect(SMCClient.Value(type: "ui8 ", bytes: [0]).encoded(256) == nil)
        #expect(SMCClient.Value(type: "ui8 ", bytes: [0]).encoded(-1) == nil)
        #expect(SMCClient.Value(type: "ui8 ", bytes: [0]).encoded(1.5) == nil)
        #expect(SMCClient.Value(type: "flt ", bytes: [0, 0, 0, 0]).encoded(.nan) == nil)
        #expect(SMCClient.Value(type: "sp78", bytes: [0, 0]).encoded(1) == nil)
    }

    @Test func onlyModeOneIsManual() {
        #expect(FanReading.isManualMode(1))
        #expect(!FanReading.isManualMode(0))
        // What both fans of this Mac report while the system runs them.
        #expect(!FanReading.isManualMode(3))
    }

    @Test func aStoppedFanHasNoShare() {
        #expect(FanReading(id: 0, rpm: 0, minimum: 1350, maximum: 5349).share == 0)
    }
}

struct FanHelperServiceTests {
    private func service(_ smc: FakeSMC, pauses: PauseLog = PauseLog()) -> FanHelperService {
        FanHelperService(smc: smc) { pauses.add($0) }
    }

    final class PauseLog: @unchecked Sendable {
        // @unchecked: tests run the service on one thread.
        private(set) var values: [TimeInterval] = []

        func add(_ value: TimeInterval) {
            values.append(value)
        }
    }

    @Test func aDirectModeWriteIsTriedFirst() {
        let smc = FakeSMC()
        #expect(service(smc).execute(FanCommand(fan: 0, action: .target(3000))))
        #expect(smc.writtenKeys == ["F0Md", "F0Tg"])
        #expect(smc.number("F0Md") == 1)
        #expect(smc.number("F0Tg") == 3000)
    }

    @Test func aRefusedModeWriteUnlocksWithTheTestKey() {
        let smc = FakeSMC()
        let pauses = PauseLog()
        smc.refusals["F0Md"] = 3
        #expect(service(smc, pauses: pauses).execute(FanCommand(fan: 0, action: .max)))
        #expect(smc.writtenKeys == ["Ftst", "F0Md", "F0Tg"])
        #expect(pauses.values.first == 3)
    }

    @Test func givingUpOnUnlockLeavesNothingBehind() {
        let smc = FakeSMC()
        smc.refusals["F0Md"] = 1000
        #expect(!service(smc).execute(FanCommand(fan: 0, action: .max)))
        #expect(smc.number("Ftst") == 0)
        #expect(!smc.writtenKeys.contains("F0Tg"))
    }

    @Test func unlockWaitsLongEnoughForASlowHandover() {
        let smc = FakeSMC()
        smc.refusals["F0Md"] = 100
        #expect(service(smc).execute(FanCommand(fan: 0, action: .max)))
    }

    @Test func noTestKeyMeansNoUnlock() {
        let smc = FakeSMC(hasTestKey: false)
        smc.refusals["F0Md"] = 1
        #expect(!service(smc).execute(FanCommand(fan: 0, action: .max)))
    }

    @Test func aFanInManualModeIsNotUnlockedAgain() {
        let smc = FakeSMC(mode: 1)
        #expect(service(smc).execute(FanCommand(fan: 0, action: .target(3000))))
        #expect(smc.writtenKeys == ["F0Tg"])
    }

    @Test func worksWithTheLowerCaseModeKey() {
        let smc = FakeSMC(modeKey: "md")
        #expect(service(smc).execute(FanCommand(fan: 1, action: .max)))
        #expect(smc.writtenKeys == ["F1md", "F1Tg"])
    }

    @Test func maxUsesTheSMCsOwnMaximum() {
        let smc = FakeSMC()
        #expect(service(smc).execute(FanCommand(fan: 0, action: .max)))
        #expect(smc.number("F0Tg") == 5349)
    }

    @Test(arguments: [(9000.0, 5349.0), (10.0, 1350.0), (-500.0, 1350.0)])
    func targetsAreClampedByTheHelperItself(rpm: Double, expected: Double) {
        let smc = FakeSMC()
        #expect(service(smc).execute(FanCommand(fan: 0, action: .target(rpm))))
        #expect(smc.number("F0Tg") == expected)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonsenseTargetsAreRefused(rpm: Double) {
        let smc = FakeSMC()
        #expect(!service(smc).execute(FanCommand(fan: 0, action: .target(rpm))))
        #expect(smc.writes.isEmpty)
    }

    @Test(arguments: [2, 99, -1])
    func unknownFansAreRefused(fan: Int) {
        let smc = FakeSMC()
        #expect(!service(smc).execute(FanCommand(fan: fan, action: .max)))
        #expect(smc.writes.isEmpty)
    }

    @Test func aFanWithoutLimitsIsRefused() {
        let smc = FakeSMC()
        smc.set("F0Mx", nil)
        #expect(!service(smc).execute(FanCommand(fan: 0, action: .max)))
        #expect(smc.writes.isEmpty)
    }

    @Test func autoKeepsTheTestKeyWhileAnotherFanIsManual() {
        let smc = FakeSMC(mode: 1)
        smc.set("Ftst", .init(type: "ui8 ", bytes: [1]))
        #expect(service(smc).execute(FanCommand(fan: 0, action: .auto)))
        #expect(smc.number("F0Md") == 0)
        #expect(smc.number("Ftst") == 1)
        #expect(service(smc).execute(FanCommand(fan: 1, action: .auto)))
        #expect(smc.number("Ftst") == 0)
    }

    @Test func restoreClearsModesBeforeTheTestKey() {
        let smc = FakeSMC(mode: 1)
        smc.set("Ftst", .init(type: "ui8 ", bytes: [1]))
        #expect(service(smc).restoreAuto())
        #expect(smc.writtenKeys == ["F0Md", "F1Md", "Ftst"])
    }

    @Test func restoreRetriesARefusedWrite() {
        let smc = FakeSMC(mode: 1)
        smc.refusals["F0Md"] = 2
        #expect(service(smc).restoreAuto())
        #expect(smc.number("F0Md") == 0)
    }

    @Test func restoreReportsAFanItCouldNotFree() {
        let smc = FakeSMC(mode: 1)
        smc.refusals["F0Md"] = 1000
        #expect(!service(smc).restoreAuto())
        #expect(smc.number("F1Md") == 0)
        #expect(service(smc).hasManualFans)
    }

    @Test func restoreLeavesASystemRunFanUntouched() {
        // Mode 3 is the system at work: launching the helper must not write anything.
        let smc = FakeSMC(mode: 3)
        #expect(service(smc).restoreAuto())
        #expect(smc.writes.isEmpty)
        #expect(!service(smc).hasManualFans)
    }
}

struct FanKeyTests {
    @Test(arguments: ["F0Md", "F1md", "F0Tg", "F9Tg", "Ftst"])
    func fanControlKeysAreWritable(key: String) {
        #expect(FanHelperService.isWritable(key))
    }

    @Test(arguments: ["F0Mn", "F0Mx", "F0Ac", "FNum", "TC0P", "MSLD", "BCLM", "", "F0Md ", "F10Tg", "XF0Md"])
    func everythingElseIsNot(key: String) {
        #expect(!FanHelperService.isWritable(key))
    }
}

struct FanWatchdogTests {
    @Test func expiresOnlyAfterTenSilentSeconds() {
        var watchdog = FanWatchdog(now: 0)
        watchdog.contact(at: 100)
        #expect(!watchdog.hasExpired(at: 110))
        #expect(watchdog.hasExpired(at: 110.1))
    }

    @Test func anyContactRestartsIt() {
        var watchdog = FanWatchdog(now: 0)
        watchdog.contact(at: 9)
        #expect(!watchdog.hasExpired(at: 15))
    }

    @Test func connectingAloneProvesNothing() {
        var watchdog = FanWatchdog(now: 0)
        watchdog.clientConnected()
        #expect(watchdog.hasExpired(at: 11))
    }

    @Test func theLastClientLeavingCounts() {
        var watchdog = FanWatchdog(now: 0)
        watchdog.clientConnected()
        watchdog.clientConnected()
        let first = watchdog.clientLeft()
        let second = watchdog.clientLeft()
        let extra = watchdog.clientLeft()
        #expect(!first)
        #expect(second)
        #expect(extra)
    }
}

struct FanHelperIdentityTests {
    @Test func pinsTheIdentifierAndTheTeam() {
        let requirement = FanHelperIdentity.requirement(identifier: "a.b", team: "ABCDE12345")
        #expect(requirement == """
        identifier "a.b" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345"
        """)
    }

    @Test(arguments: [nil, "", "$(TEAM)", "A\" or anchor apple"])
    func noUsableTeamMeansNoRequirement(team: String?) {
        #expect(FanHelperIdentity.requirement(identifier: "a.b", team: team) == nil)
    }

    @Test func wireCommandsRoundTrip() {
        for action in [FanCommand.Action.auto, .max, .target(3000)] {
            let command = FanCommand(fan: 1, action: action)
            let wire = command.wire
            #expect(FanCommand(fan: 1, wireAction: wire.action.rawValue, rpm: wire.rpm) == command)
        }
    }

    @Test func malformedWireCommandsAreRefused() {
        #expect(FanCommand(fan: 0, wireAction: 3, rpm: 0) == nil)
        #expect(FanCommand(fan: 0, wireAction: -1, rpm: 0) == nil)
        #expect(FanCommand(fan: 0, wireAction: 2, rpm: .nan) == nil)
    }
}

/// The real XPC path, over an anonymous in-process listener with a fake SMC.
struct FanHelperXPCTests {
    private final class Clock: @unchecked Sendable {
        // @unchecked: guarded by `lock`.
        private let lock = NSLock()
        private var value: TimeInterval = 0

        var time: TimeInterval {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private final class Harness: @unchecked Sendable {
        // @unchecked: everything is set once in init.
        let smc: FakeSMC
        let server: FanHelperServer
        let listener = NSXPCListener.anonymous()

        let clock = Clock()
        let queue = DispatchQueue(label: "test.helper")

        init(requirement: String? = nil, acceptsUnsigned: Bool = true, mode: UInt8 = 3) {
            smc = FakeSMC(mode: mode)
            let clock = clock
            server = FanHelperServer(
                service: FanHelperService(smc: smc) { _ in },
                queue: queue,
                requirement: requirement,
                acceptsUnsigned: acceptsUnsigned,
                now: { clock.time }
            )
            listener.delegate = server
            listener.resume()
        }

        func connect(onLost: @escaping @Sendable () -> Void = {}) -> FanHelperConnection {
            FanHelperConnection(connection: NSXPCConnection(listenerEndpoint: listener.endpoint), onLost: onLost)
        }
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func commandsReachTheSMC() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .target(3000))))
        #expect(harness.smc.number("F0Tg") == 3000)
        #expect(await client.heartbeat())
        client.disconnect()
    }

    @Test func aRefusedCommandComesBackFalse() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 7, action: .max)) == false)
        client.disconnect()
    }

    @Test func theClientGoingAwayRestoresAuto() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))
        #expect(harness.smc.number("F0Md") == 1)

        client.disconnect()

        await waitUntil { harness.smc.number("F0Md") == 0 }
        #expect(harness.smc.number("F0Md") == 0)
    }

    @Test func silenceRestoresAutoAfterTenSeconds() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))

        harness.clock.time = 10
        harness.queue.sync { harness.server.checkWatchdog() }
        #expect(harness.smc.number("F0Md") == 1)

        harness.clock.time = 10.5
        harness.queue.sync { harness.server.checkWatchdog() }
        #expect(harness.smc.number("F0Md") == 0)
        client.disconnect()
    }

    @Test func aHeartbeatKeepsControl() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))

        harness.clock.time = 9
        #expect(await client.heartbeat())
        harness.clock.time = 15
        harness.queue.sync { harness.server.checkWatchdog() }

        #expect(harness.smc.number("F0Md") == 1)
        client.disconnect()
    }

    @Test func aHeartbeatAdmitsThatTheFansWereGivenBack() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))
        #expect(await client.heartbeat())

        harness.clock.time = 11
        harness.queue.sync { harness.server.checkWatchdog() }

        #expect(await client.heartbeat() == false)
        client.disconnect()
    }

    @Test func aHeartbeatBeforeAnyCommandHoldsNothing() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.heartbeat() == false)
        client.disconnect()
    }

    @Test func releasingEveryFanDisarmsTheWatchdog() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))
        #expect(await client.send(FanCommand(fan: 0, action: .auto)))
        #expect(await client.heartbeat() == false)
        client.disconnect()
    }

    @Test func aNewConnectionDoesNotRestartTheWatchdog() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))

        harness.clock.time = 11
        let stranger = NSXPCConnection(listenerEndpoint: harness.listener.endpoint)
        #expect(harness.server.listener(harness.listener, shouldAcceptNewConnection: stranger))
        harness.queue.sync { harness.server.checkWatchdog() }

        #expect(harness.smc.number("F0Md") == 0)
        stranger.invalidate()
        client.disconnect()
    }

    @Test func anIdleHelperLeavesTheSMCAlone() {
        let harness = Harness()
        harness.clock.time = 100
        harness.queue.sync { harness.server.checkWatchdog() }
        #expect(harness.smc.writes.isEmpty)
    }

    @Test func aFailedRestoreIsTriedAgain() async {
        let harness = Harness()
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)))
        harness.smc.refusals["F0Md"] = 1000

        harness.clock.time = 11
        harness.queue.sync { harness.server.checkWatchdog() }
        #expect(harness.smc.number("F0Md") == 1)

        harness.smc.refusals["F0Md"] = 0
        harness.queue.sync { harness.server.checkWatchdog() }
        #expect(harness.smc.number("F0Md") == 0)
        client.disconnect()
    }

    @Test func aBuildWithoutATeamIsRefused() async {
        let harness = Harness(requirement: nil, acceptsUnsigned: false)
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)) == false)
        #expect(harness.smc.writes.isEmpty)
    }

    @Test func aClientFailingTheRequirementIsRefused() async {
        // The test runner is not signed by this team, so the check itself must turn it away.
        let requirement = FanHelperIdentity.requirement(identifier: "no.such.app", team: "AAAAAAAAAA")
        let harness = Harness(requirement: requirement, acceptsUnsigned: false)
        let client = harness.connect()
        #expect(await client.send(FanCommand(fan: 0, action: .max)) == false)
        #expect(harness.smc.writes.isEmpty)
    }

    @Test func startupTakesBackAFanLeftInManualMode() async {
        let harness = Harness(mode: 1)
        harness.server.start()
        await waitUntil { harness.smc.number("F0Md") == 0 }
        #expect(harness.smc.number("F0Md") == 0)
        #expect(harness.smc.number("F1Md") == 0)
    }

    @Test func shutdownRestoresAuto() {
        let harness = Harness(mode: 1)
        harness.server.shutdown()
        #expect(harness.smc.number("F0Md") == 0)
    }
}
