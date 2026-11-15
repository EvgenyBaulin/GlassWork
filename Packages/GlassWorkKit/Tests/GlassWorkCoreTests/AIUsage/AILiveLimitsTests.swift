import Foundation
@testable import GlassWorkCore
import Testing

/// A clock the test moves by hand.
private final class Clock: @unchecked Sendable {
    // Why unchecked: the lock guards `date`.
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.withLock { date }
    }

    func advance(minutes: Double) {
        lock.withLock { date = date.addingTimeInterval(minutes * 60) }
    }
}

private final class FakeSession: LineSessionRunning, @unchecked Sendable {
    // Why unchecked: the lock guards `count`.
    private let lock = NSLock()
    private var count = 0
    private let answer: @Sendable () throws -> String

    init(answer: @escaping @Sendable () throws -> String) {
        self.answer = answer
    }

    var calls: Int {
        lock.withLock { count }
    }

    func exchange(
        _: String,
        arguments _: [String],
        send _: [String],
        until _: @escaping @Sendable (String) -> Bool,
        timeout _: TimeInterval
    ) async throws -> String {
        lock.withLock { count += 1 }
        return try answer()
    }
}

private let claudeAnswer = #"{"num_turns":0,"total_cost_usd":0,"#
    + #""result":"Current session: 30% used\nCurrent week (all models): 10% used"}"#
private let codexAnswer = #"{"id":2,"result":{"rateLimits":{"primary":"#
    + #"{"usedPercent":40,"windowDurationMins":300,"resetsAt":1800003600}}}}"#

struct AILiveLimitsTests {
    private let clock = Clock()

    private func limits(
        runner: FakeRunner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: claudeAnswer, stderr: "") },
        session: FakeSession = FakeSession { codexAnswer },
        installed: Bool = true
    ) -> AILiveLimits {
        let clock = clock
        return AILiveLimits(
            runner: runner,
            session: session,
            clientVersion: "0.1.0",
            locate: { installed ? "/usr/local/bin/\($0)" : nil },
            now: { clock.now }
        )
    }

    private func claudeFile(minutesOld: Double) -> AIToolUsage {
        AIToolUsage(
            tool: .claudeCode,
            windows: [AIWindow(kind: .fiveHour, used: 0.05, resetsAt: nil)],
            updatedAt: clock.now.addingTimeInterval(-minutesOld * 60)
        )
    }

    @Test func freshFileSkipsTheClaudeCall() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: claudeAnswer, stderr: "") }
        let file = claudeFile(minutesOld: 5)
        #expect(await limits(runner: runner).refined(file) == file)
        #expect(runner.calls.isEmpty)
    }

    @Test func staleFileCallsClaudeOnceIn15Minutes() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: claudeAnswer, stderr: "") }
        let limits = limits(runner: runner)
        let first = await limits.refined(claudeFile(minutesOld: 60))
        #expect(first.source == .tool)
        #expect(first.windows.map(\.used) == [0.3, 0.1])
        clock.advance(minutes: 5)
        _ = await limits.refined(claudeFile(minutesOld: 65))
        clock.advance(minutes: 11)
        _ = await limits.refined(claudeFile(minutesOld: 76))
        #expect(runner.calls.count == 2)
        #expect(runner.calls.first == ["/usr/local/bin/claude"] + ClaudeUsageCommand.arguments)
    }

    @Test func spentTurnsStopsClaudeForGood() async {
        let runner = FakeRunner { _, _ in
            ProcessOutput(status: 0, stdout: #"{"num_turns":1,"result":""}"#, stderr: "")
        }
        let limits = limits(runner: runner)
        let file = claudeFile(minutesOld: 60)
        #expect(await limits.refined(file) == file)
        clock.advance(minutes: 60)
        _ = await limits.refined(claudeFile(minutesOld: 120))
        #expect(runner.calls.count == 1)
    }

    @Test func failedClaudeCallKeepsTheFileAndWaits() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "error") }
        let limits = limits(runner: runner)
        let file = claudeFile(minutesOld: 60)
        #expect(await limits.refined(file) == file)
        clock.advance(minutes: 10)
        _ = await limits.refined(file)
        #expect(runner.calls.count == 1)
        clock.advance(minutes: 6)
        _ = await limits.refined(file)
        #expect(runner.calls.count == 2)
    }

    @Test func missingClaudeIsQuiet() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: claudeAnswer, stderr: "") }
        let file = claudeFile(minutesOld: 60)
        #expect(await limits(runner: runner, installed: false).refined(file) == file)
        #expect(runner.calls.isEmpty)
    }

    @Test func newerFileBeatsCachedLive() async {
        let limits = limits()
        _ = await limits.refined(claudeFile(minutesOld: 60))
        clock.advance(minutes: 20)
        let reopened = claudeFile(minutesOld: 1)
        #expect(await limits.refined(reopened) == reopened)
    }

    @Test func liveBeatsUnreadableFile() async {
        let unreadable = AIToolUsage(tool: .claudeCode, isUnreadable: true)
        let result = await limits().refined(unreadable)
        #expect(result.source == .tool)
    }

    @Test func codexAskedAtMostEvery5Minutes() async {
        let session = FakeSession { codexAnswer }
        let limits = limits(session: session)
        let file = AIToolUsage(tool: .codex)
        let first = await limits.refined(file)
        #expect(first.windows.map(\.used) == [0.4])
        clock.advance(minutes: 2)
        _ = await limits.refined(file)
        clock.advance(minutes: 4)
        _ = await limits.refined(file)
        #expect(session.calls == 2)
    }

    @Test func codexTimeoutKeepsTheLogValue() async {
        let session = FakeSession { throw ProcessRunnerError.timedOut("codex") }
        let file = AIToolUsage(
            tool: .codex,
            windows: [AIWindow(kind: .week, used: 0.2, resetsAt: nil)],
            updatedAt: clock.now
        )
        #expect(await limits(session: session).refined(file) == file)
    }

    @Test func otherToolsPassThrough() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: claudeAnswer, stderr: "") }
        let session = FakeSession { codexAnswer }
        let gemini = AIToolUsage(tool: .geminiCLI)
        #expect(await limits(runner: runner, session: session).refined(gemini) == gemini)
        #expect(runner.calls.isEmpty)
        #expect(session.calls == 0)
    }
}
