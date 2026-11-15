import Foundation
@testable import GlassWorkCore
import Testing

struct SleepBlockerTests {
    /// A trimmed copy of what `IOPMCopyAssertionsByProcess` gave on a real Mac, keyed by pid.
    private func assertions() throws -> [Int32: [[String: Any]]] {
        let plist = try PropertyListSerialization.propertyList(from: fixture("pm-assertions.plist"), format: nil)
        let byPID = try #require(plist as? [String: [[String: Any]]])
        return Dictionary(uniqueKeysWithValues: byPID.compactMap { key, value in Int32(key).map { ($0, value) } })
    }

    private func blockers() throws -> [SleepBlocker] {
        try SleepBlockers.parse(assertions(), ownPID: 4242)
    }

    @Test func listsProgramsOldestFirstWithoutMacOSOwnOrGlassWork() throws {
        #expect(try blockers().map(\.pid) == [83453, 93223, 93380, 95990])
    }

    @Test func leavesOutBackgroundTasksAndReleasedAssertions() throws {
        let processes = try Set(blockers().map(\.process))
        #expect(!processes.contains("nsurlsessiond"))
        #expect(!processes.contains("Safari"))
        #expect(!processes.contains("powerd"))
    }

    @Test func aTimedCaffeinateKnowsWhenItEnds() throws {
        let timed = try #require(blockers().first { $0.pid == 95990 })
        #expect(timed.isCaffeinate)
        #expect(timed.kind == .system)
        #expect(timed.ends == timed.started?.addingTimeInterval(300))
        #expect(timed.whileProcess == nil)
    }

    @Test func aCaffeinateForACommandOrAProcessLastsWhileItLives() throws {
        let list = try blockers()
        #expect(list.first { $0.pid == 93223 }?.whileProcess == 93222)
        let waiting = try #require(list.first { $0.pid == 83453 })
        #expect(waiting.whileProcess == 78322)
        #expect(waiting.kind == .display)
        #expect(waiting.ends == nil)
    }

    @Test func otherProgramsKeepTheirReason() throws {
        let build = try #require(blockers().first { $0.pid == 93380 })
        #expect(build.process == "xcodebuild")
        #expect(build.reason == "Xcode running tests.")
        #expect(!build.isCaffeinate)
    }

    @Test func readsDetailsOfACommand() {
        #expect(SleepBlockers.onBehalfOf("caffeinate asserting on behalf of '/usr/bin/perl' (pid 99094)") == 99094)
        #expect(SleepBlockers.onBehalfOf("caffeinate asserting for 300 secs") == nil)
        #expect(SleepBlockers.onBehalfOf(nil) == nil)
    }

    @Test func readsThisMacWithoutCrashing() {
        _ = SleepBlockers.read()
    }
}

struct CaffeinateStopperTests {
    @Test func stopsOnlyACaffeinateOfThisUser() {
        typealias Facts = CaffeinateStopper.ProcessFacts
        let user: uid_t = 501
        let mine = CaffeinateStopper.canStop(Facts(name: "caffeinate", uid: user), as: user)
        let roots = CaffeinateStopper.canStop(Facts(name: "caffeinate", uid: 0), as: user)
        let other = CaffeinateStopper.canStop(Facts(name: "xcodebuild", uid: user), as: user)
        let gone = CaffeinateStopper.canStop(nil, as: user)
        #expect([mine, roots, other, gone] == [true, false, false, false])
    }

    @Test func refusesAProcessThatIsNotCaffeinate() {
        #expect(!CaffeinateStopper.stop(getpid()))
    }

    @Test func stopsARealCaffeinate() async throws {
        let child = Process()
        child.executableURL = URL(filePath: "/usr/bin/caffeinate")
        child.arguments = ["-i", "-t", "60"]
        try child.run()
        defer {
            if child.isRunning {
                child.terminate()
            }
        }
        for _ in 0 ..< 200 where CaffeinateStopper.facts(of: child.processIdentifier)?.name != "caffeinate" {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(CaffeinateStopper.stop(child.processIdentifier))
        child.waitUntilExit()
        #expect(child.terminationReason == .uncaughtSignal)
    }
}
