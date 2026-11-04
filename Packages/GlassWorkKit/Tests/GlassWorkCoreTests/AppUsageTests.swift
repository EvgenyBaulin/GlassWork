import Foundation
@testable import GlassWorkCore
import Testing

private let safari = RunningAppInfo(
    pid: 100,
    name: "Safari",
    bundleID: "com.apple.Safari",
    path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
    role: .regular
)
private let slack = RunningAppInfo(
    pid: 200,
    name: "Slack",
    bundleID: "com.tinyspeck.slackmacgap",
    path: "/Applications/Slack.app",
    role: .regular
)
private let xcode = RunningAppInfo(
    pid: 300,
    name: "Xcode",
    bundleID: "com.apple.dt.Xcode",
    path: "/Applications/Xcode.app",
    role: .regular
)
private let simulator = RunningAppInfo(
    pid: 310,
    name: "Simulator",
    bundleID: "com.apple.iphonesimulator",
    path: "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app",
    role: .regular
)

private func facts(_ list: ProcessFacts...) -> [Int32: ProcessFacts] {
    Dictionary(uniqueKeysWithValues: list.map { ($0.pid, $0) })
}

private func process(_ pid: Int32, parent: Int32 = 1, responsible: Int32? = nil, path: String?) -> ProcessFacts {
    ProcessFacts(pid: pid, parent: parent, responsible: responsible ?? pid, path: path)
}

struct AppOwnershipTests {
    private let apps = [safari, slack, xcode, simulator]

    private func owner(_ fact: ProcessFacts, others: [ProcessFacts] = []) -> String? {
        let all = Dictionary(uniqueKeysWithValues: ([fact] + others).map { ($0.pid, $0) })
        return AppUsageGrouping.owners(of: [fact.pid], facts: all, apps: apps)[fact.pid]
    }

    @Test
    func theAppIsItsOwnOwner() {
        #expect(owner(process(100, path: "/any/Safari")) == safari.id)
    }

    @Test
    func aHelperAppNestedInFrameworksCountsWithItsApp() {
        let path = "/Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app/Contents/MacOS/Slack Helper"
        #expect(owner(process(201, path: path)) == slack.id)
    }

    @Test
    func anExtensionInPlugInsCountsWithItsApp() {
        let path = "/Applications/Slack.app/Contents/PlugIns/Share.appex/Contents/MacOS/Share"
        #expect(owner(process(202, path: path)) == slack.id)
    }

    @Test
    func aSystemServiceFollowsTheAppResponsibleForIt() {
        let path = "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/WebContent"
        #expect(owner(process(101, responsible: 100, path: path)) == safari.id)
    }

    @Test
    func aServiceOfAHelperLeadsBackThroughTheHelpersBundle() {
        let helper = process(205, path: "/Applications/Slack.app/Contents/MacOS/Slack Helper")
        let service = process(206, responsible: 205, path: "/System/Library/Frameworks/Foo.framework/Service")
        #expect(owner(service, others: [helper]) == slack.id)
    }

    @Test
    func aShellStartedByTheAppCountsWithIt() {
        let shell = process(320, parent: 300, path: "/bin/zsh")
        let tool = process(321, parent: 320, path: "/usr/local/bin/node")
        #expect(owner(tool, others: [shell]) == xcode.id)
    }

    @Test
    func theInnermostBundleWinsForAnAppInsideAnApp() {
        let path = "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Helper"
        #expect(owner(process(311, path: path)) == simulator.id)
    }

    @Test
    func aDaemonHasNoOwner() {
        #expect(owner(process(900, path: "/usr/libexec/trustd")) == nil)
    }

    @Test
    func aSimilarlyNamedBundleIsNotTheApp() {
        #expect(owner(process(901, path: "/Applications/Slack.app.old/Contents/MacOS/Slack")) == nil)
    }

    @Test
    func aParentLoopEnds() {
        let first = process(910, parent: 911, path: nil)
        let second = process(911, parent: 910, path: nil)
        #expect(owner(first, others: [second]) == nil)
    }
}

struct AppUsageSumTests {
    private func usage(
        _ counters: [ProcessCounters],
        previous: [ProcessCounters] = [],
        seconds: TimeInterval? = 10,
        owners: [Int32: String]
    ) -> [AppUsage] {
        AppUsageGrouping.usage(
            apps: [slack, xcode],
            counters: counters,
            previous: Dictionary(uniqueKeysWithValues: previous.map { ($0.pid, $0) }),
            seconds: seconds,
            owners: owners
        )
    }

    private func counters(_ pid: Int32, start: UInt64 = 1, seconds: Double, memory: UInt64 = 0) -> ProcessCounters {
        ProcessCounters(pid: pid, start: start, cpuNanoseconds: UInt64(seconds * 1e9), memory: memory)
    }

    @Test
    func addsHelpersToTheirApp() throws {
        let result = usage(
            [counters(200, seconds: 3, memory: 100), counters(201, seconds: 5, memory: 50)],
            previous: [counters(200, seconds: 2), counters(201, seconds: 3)],
            owners: [200: slack.id, 201: slack.id]
        )
        let app = try #require(result.first)
        #expect(app.memory == 150)
        #expect(app.helpers == 1)
        #expect(abs(app.cpu - 30) < 0.001)
    }

    @Test
    func aNewProcessCountsAllItsTime() throws {
        let result = usage([counters(200, seconds: 1)], owners: [200: slack.id])
        #expect(try abs(#require(result.first).cpu - 10) < 0.001)
    }

    @Test
    func aReusedPidDoesNotCarryTheOldTotal() throws {
        let result = usage(
            [counters(200, start: 9, seconds: 1)],
            previous: [counters(200, start: 1, seconds: 500)],
            owners: [200: slack.id]
        )
        #expect(try abs(#require(result.first).cpu - 10) < 0.001)
    }

    @Test
    func aCounterGoingBackwardsIsNotNegative() throws {
        let result = usage([counters(200, seconds: 1)], previous: [counters(200, seconds: 5)], owners: [200: slack.id])
        #expect(try #require(result.first).cpu == 0)
    }

    @Test
    func theFirstReadHasMemoryButNoCPU() throws {
        let result = usage([counters(200, seconds: 100, memory: 5)], seconds: nil, owners: [200: slack.id])
        let app = try #require(result.first)
        #expect(app.cpu == 0)
        #expect(app.memory == 5)
    }

    @Test
    func anAppWhoseProcessCouldNotBeReadIsLeftOut() {
        let result = usage([counters(200, seconds: 1)], owners: [200: slack.id])
        #expect(result.map(\.id) == [slack.id])
    }

    @Test
    func aProcessOfNoListedAppIsIgnored() {
        #expect(usage([counters(999, seconds: 1)], owners: [:]).isEmpty)
    }
}

struct AppListTests {
    private let heavy = AppUsage(id: "h", pid: 1, name: "Heavy", cpu: 5, memory: 900)
    private let busy = AppUsage(id: "b", pid: 2, name: "Busy", cpu: 80, memory: 100)
    private let idle = AppUsage(id: "a", pid: 3, name: "Idle", cpu: 5, memory: 100)

    @Test
    func sortsHeaviestFirst() {
        #expect([busy, heavy].sorted(by: .memory).map(\.id) == ["h", "b"])
        #expect([heavy, busy].sorted(by: .cpu).map(\.id) == ["b", "h"])
    }

    @Test
    func equalAppsKeepAStableOrder() {
        #expect([idle, busy].sorted(by: .memory).map(\.id) == ["b", "a"])
        #expect([busy, idle].sorted(by: .memory).map(\.id) == ["b", "a"])
    }

    @Test
    func aListUnderThePointerKeepsItsOrder() {
        #expect([busy, heavy, idle].arranged(following: ["a", "h", "b"]).map(\.id) == ["a", "h", "b"])
    }

    @Test
    func aNewAppGoesLastWhileTheOrderIsHeld() {
        #expect([idle, heavy].arranged(following: ["h"]).map(\.id) == ["h", "a"])
    }

    @Test
    func aQuitAppLeavesAHeldOrder() {
        #expect([heavy].arranged(following: ["b", "h"]).map(\.id) == ["h"])
    }

    @Test
    func searchPutsStartsOfNamesFirst() {
        let timer = AppUsage(id: "t", pid: 4, name: "Sleep Timer", cpu: 0, memory: 0)
        let slack = AppUsage(id: "s", pid: 5, name: "Slack", cpu: 0, memory: 0)
        let widget = AppUsage(id: "w", pid: 6, name: "Mysl", cpu: 0, memory: 0)
        #expect([widget, timer, slack].matching("sl").map(\.id) == ["t", "s", "w"])
        #expect([slack].matching("SL").count == 1)
        #expect([slack].matching("  ").count == 1)
        #expect([slack].matching("xyz").isEmpty)
    }

    @Test
    func systemMenuBarAppsAreNotListed() {
        let info = { (role: RunningAppInfo.Role, path: String?) in
            RunningAppInfo(pid: 1, name: "x", bundleID: nil, path: path, role: role).isListed
        }
        #expect(info(.regular, "/System/Applications/Music.app"))
        #expect(info(.accessory, "/Applications/Bartender.app"))
        #expect(!info(.accessory, "/System/Library/CoreServices/Spotlight.app"))
        #expect(!info(.accessory, nil))
        #expect(!info(.background, "/Applications/Foo.app"))
    }

    @Test
    func theBundleIDOutlivesAMove() {
        let first = RunningAppInfo(pid: 1, name: "A", bundleID: "x.y", path: "/one/A.app", role: .regular)
        let second = RunningAppInfo(pid: 2, name: "A", bundleID: "x.y", path: "/two/A.app", role: .regular)
        #expect(first.id == second.id)
    }

    @Test
    func coreShareFormats() {
        #expect(Format.corePercent(0) == "0%")
        #expect(Format.corePercent(0.4) == "0.4%")
        #expect(Format.corePercent(24.2) == "24%")
        #expect(Format.corePercent(180) == "180%")
    }

    @Test
    func sizesInListsStayShort() {
        #expect(Format.size(6_200_000_000) == "6.2 GB")
        #expect(Format.size(620_000_000) == "620 MB")
        #expect(Format.size(21_400_000_000) == "21.4 GB")
    }
}

struct TimebaseTests {
    @Test
    func turnsAppleSiliconTicksIntoNanoseconds() {
        #expect(Timebase(numerator: 125, denominator: 3).nanoseconds(24_000_000) == 1_000_000_000)
    }

    @Test
    func leavesIntelTimeAlone() {
        #expect(Timebase(numerator: 1, denominator: 1).nanoseconds(5) == 5)
    }
}

/// A process list the test writes itself. Nothing here looks at the real system.
private final class FakeTable: ProcessTable, @unchecked Sendable {
    // Only ever touched from the one test that owns it, one call at a time.
    var counters: [ProcessCounters] = []
    var factsAsked: [Int32] = []
    var factsByPID: [Int32: ProcessFacts] = [:]

    func pids() -> [Int32] {
        counters.map(\.pid)
    }

    func counters(of pid: Int32) -> ProcessCounters? {
        counters.first { $0.pid == pid }
    }

    func facts(of pid: Int32) -> ProcessFacts {
        factsAsked.append(pid)
        return factsByPID[pid] ?? ProcessFacts(pid: pid, parent: 1, responsible: pid, path: nil)
    }
}

struct AppUsageReaderTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func seconds(_ value: Double) -> UInt64 {
        UInt64(value * 1e9)
    }

    @Test
    func theSecondReadHasCPU() async throws {
        let table = FakeTable()
        let reader = AppUsageReader(table: table)
        table.counters = [ProcessCounters(pid: 200, start: 1, cpuNanoseconds: seconds(1), memory: 10)]
        let first = await reader.read([slack], at: start)
        #expect(!first.hasCPU)
        table.counters = [ProcessCounters(pid: 200, start: 1, cpuNanoseconds: seconds(4), memory: 10)]
        let second = await reader.read([slack], at: start.addingTimeInterval(60))
        #expect(second.hasCPU)
        #expect(try abs(#require(second.apps.first).cpu - 5) < 0.001)
    }

    @Test
    func aLongGapStartsOver() async {
        let table = FakeTable()
        let reader = AppUsageReader(table: table)
        table.counters = [ProcessCounters(pid: 200, start: 1, cpuNanoseconds: seconds(1), memory: 10)]
        _ = await reader.read([slack], at: start)
        let next = await reader.read([slack], at: start.addingTimeInterval(3600))
        #expect(!next.hasCPU)
    }

    @Test
    func factsAreAskedForOncePerProcess() async {
        let table = FakeTable()
        let reader = AppUsageReader(table: table)
        table.counters = [ProcessCounters(pid: 200, start: 1, cpuNanoseconds: 0, memory: 10)]
        _ = await reader.read([slack], at: start)
        _ = await reader.read([slack], at: start.addingTimeInterval(5))
        _ = await reader.read([slack], at: start.addingTimeInterval(10))
        #expect(table.factsAsked == [200])
    }

    @Test
    func aReusedPidIsLookedAtAgain() async {
        let table = FakeTable()
        let reader = AppUsageReader(table: table)
        table.factsByPID[201] = ProcessFacts(pid: 201, parent: 200, responsible: 201, path: nil)
        table.counters = [
            ProcessCounters(pid: 200, start: 1, cpuNanoseconds: 0, memory: 10),
            ProcessCounters(pid: 201, start: 1, cpuNanoseconds: 0, memory: 10),
        ]
        let first = await reader.read([slack], at: start)
        #expect(first.apps.first?.helpers == 1)
        table.factsByPID[201] = ProcessFacts(pid: 201, parent: 1, responsible: 201, path: "/usr/libexec/other")
        table.counters[1].start = 2
        let second = await reader.read([slack], at: start.addingTimeInterval(5))
        #expect(second.apps.first?.helpers == 0)
    }

    @Test
    func aNewAppClaimsProcessesAlreadySeen() async {
        let table = FakeTable()
        let reader = AppUsageReader(table: table)
        table.factsByPID[201] = ProcessFacts(pid: 201, parent: 200, responsible: 201, path: nil)
        table.counters = [
            ProcessCounters(pid: 200, start: 1, cpuNanoseconds: 0, memory: 10),
            ProcessCounters(pid: 201, start: 1, cpuNanoseconds: 0, memory: 10),
        ]
        _ = await reader.read([], at: start)
        let next = await reader.read([slack], at: start.addingTimeInterval(5))
        #expect(next.apps.first?.helpers == 1)
    }
}

/// Reads the real process list and nothing else: nothing is started, signalled or written.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AppUsageCostTests {
    private static func ownCPUTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }

    private let thisTest = RunningAppInfo(
        pid: ProcessInfo.processInfo.processIdentifier,
        name: "Test",
        bundleID: nil,
        path: nil,
        role: .regular
    )

    /// The app is watched for its own CPU use, so this keeps the price of a read in sight. The time is the whole test
    /// process, so other tests running alongside inflate it: run this one alone for the real figure.
    @Test
    func aReadStaysCheap() async {
        let reader = AppUsageReader()
        let start = Date()
        _ = await reader.read([thisTest], at: start)
        let reads = 40
        let before = Self.ownCPUTime()
        for index in 1 ... reads {
            _ = await reader.read([thisTest], at: start.addingTimeInterval(Double(index) * 60))
        }
        let perRead = (Self.ownCPUTime() - before) / Double(reads)
        let share = perRead / AppUsageStore.backgroundInterval * 100
        print("App usage read: \(perRead * 1000) ms of CPU, \(share)% of a core in the background")
        #expect(perRead < 0.05)
    }

    /// Ticks would read far too small here if they were taken for nanoseconds.
    @Test
    func aBusyProcessReadsAsOneBusyCore() async throws {
        let reader = AppUsageReader()
        let start = Date()
        _ = await reader.read([thisTest], at: start)
        var value = 0.0
        while Date().timeIntervalSince(start) < 0.4 {
            value += sin(value + 1)
        }
        let reading = await reader.read([thisTest], at: Date())
        let app = try #require(reading.apps.first)
        #expect(value != .infinity)
        #expect((40 ... 400).contains(app.cpu))
        #expect(app.memory > 1_000_000)
    }
}
