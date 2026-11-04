import Foundation
@testable import GlassWorkCore
import Testing

struct PingParserTests {
    @Test func readsTheRoundTripTime() throws {
        let output = try ProcessOutput(status: 0, stdout: fixture("ping-reply.txt"), stderr: "")
        #expect(PingParser.outcome(output) == .reply(milliseconds: 5.86))
    }

    @Test func noReplyIsATimeout() throws {
        let output = try ProcessOutput(status: 2, stdout: fixture("ping-timeout.txt"), stderr: "")
        #expect(PingParser.outcome(output) == .timeout)
    }

    @Test func unknownHostIsNotATimeout() {
        let stderr = "ping: cannot resolve no-such-host.invalid: Unknown host\n"
        #expect(PingParser.outcome(ProcessOutput(status: 68, stdout: "", stderr: stderr)) == .unresolved)
    }

    @Test func noRouteMeansTheMacIsOffline() {
        let stderr = "ping: sendto: No route to host\n"
        #expect(PingParser.outcome(ProcessOutput(status: 2, stdout: "", stderr: stderr)) == .offline)
    }

    @Test(arguments: ["1.1.1.1", "example.com", "my-host.local"])
    func acceptsHosts(host: String) {
        #expect(PingHost.isValid(host))
    }

    @Test(arguments: ["", "-f", "--help", "host name", "a;b", "$(x)", "хост", "::1"])
    func refusesAnythingThatIsNotAHost(host: String) {
        #expect(!PingHost.isValid(host))
    }

    @Test func invalidHostNeverReachesTheCommand() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: "", stderr: "") }

        #expect(await PingCollector(runner: runner).read(host: "-f") == .unresolved)
        #expect(runner.calls.isEmpty)
    }

    @Test func hostComesAfterTheEndOfOptions() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 2, stdout: "", stderr: "") }

        _ = await PingCollector(runner: runner).read(host: "1.1.1.1")

        #expect(runner.calls == [["/sbin/ping", "-n", "-c", "1", "-t", "3", "--", "1.1.1.1"]])
    }
}

struct PingLogTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func log(_ outcomes: [PingOutcome]) -> PingLog {
        var log = PingLog()
        for (index, outcome) in outcomes.enumerated() {
            log.append(outcome, at: start.addingTimeInterval(Double(index) * 30))
        }
        return log
    }

    @Test func computesStatsOverReplies() throws {
        let stats = try #require(log([
            .reply(milliseconds: 10),
            .timeout,
            .reply(milliseconds: 20),
            .reply(milliseconds: 14),
        ]).stats)

        #expect(stats.minimum == 10)
        #expect(stats.maximum == 20)
        #expect(abs(stats.average - 44.0 / 3) < 0.0001)
        #expect(stats.jitter == 8)
        #expect(stats.loss == 0.25)
    }

    @Test func hostIsDownAfterThreeMissesInARow() {
        #expect(!log([.timeout, .timeout]).isDown)
        #expect(log([.reply(milliseconds: 1), .timeout, .timeout, .timeout]).isDown)
        #expect(!log([.timeout, .timeout, .timeout, .reply(milliseconds: 1)]).isDown)
    }

    @Test func noNetworkIsNotAHostProblem() {
        let log = log([.offline, .offline, .offline])

        #expect(log.isOffline)
        #expect(!log.isDown)
    }

    @Test func upSinceStartsAfterTheLastMiss() {
        let log = log([.reply(milliseconds: 1), .timeout, .reply(milliseconds: 1), .reply(milliseconds: 1)])
        #expect(log.upSince == start.addingTimeInterval(60))
    }

    @Test func noUpSinceWhileSilent() {
        #expect(log([.reply(milliseconds: 1), .timeout]).upSince == nil)
    }

    @Test func keepsThirtyMinutes() {
        let log = log(Array(repeating: .reply(milliseconds: 1), count: 75))
        #expect(log.samples.count == PingLog.capacity)
    }

    @Test func rollingLossGrowsWithEachMiss() {
        let loss = log([.reply(milliseconds: 1), .timeout]).rollingLoss.map(\.value)
        #expect(loss == [0, 0.5])
    }
}

@MainActor
struct DeveloperStoreTests {
    private func wait(for _: DeveloperStore, _ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func readsOnlyWhatIsDemanded() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 2, stdout: "", stderr: "") }
        let store = DeveloperStore(runner: runner)

        store.tick(demand: [])
        await Task.yield()

        #expect(runner.calls.isEmpty)
    }

    @Test func waitsForTheInterval() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 2, stdout: "", stderr: "") }
        let store = DeveloperStore(runner: runner)
        let start = Date()

        store.tick(at: start, demand: [.ping])
        await wait(for: store) { store.ping.samples.count == 1 }
        store.tick(at: start.addingTimeInterval(5), demand: [.ping])
        store.tick(at: start.addingTimeInterval(31), demand: [.ping])
        await wait(for: store) { store.ping.samples.count == 2 }

        #expect(runner.calls.count == 2)
    }

    @Test func aNewHostStartsAFreshLog() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 2, stdout: "", stderr: "") }
        let store = DeveloperStore(runner: runner)

        store.tick(demand: [.ping])
        await wait(for: store) { store.ping.samples.count == 1 }
        store.options.pingHost = "9.9.9.9"

        #expect(store.ping.samples.isEmpty)
    }
}

struct DeveloperDemandTests {
    @Test func hubOnlyModulesReadOnlyWhileAPanelIsOpen() {
        var settings = AppSettings()
        settings.update(.ping) { $0.mode = .hubOnly }
        settings.update(.docker) { $0.mode = .menuBar }

        #expect(settings.developerDemand(panelOpen: false) == [.docker])
        #expect(settings.developerDemand(panelOpen: true) == [.docker, .ping])
    }

    @Test func modulesThatAreOffNeverRead() {
        #expect(AppSettings().developerDemand(panelOpen: true).isEmpty)
    }

    @Test func invalidHostInTheFileFallsBack() {
        var settings = AppSettings()
        settings.update(.ping) { $0.options[DeveloperOptions.Key.host] = "-f" }

        #expect(DeveloperOptions(settings: settings).pingHost == PingHost.fallback)
    }
}
