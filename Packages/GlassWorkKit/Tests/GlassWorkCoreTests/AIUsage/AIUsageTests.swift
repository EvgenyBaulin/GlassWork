import Foundation
@testable import GlassWorkCore
import Testing

private func aiFixture(_ name: String) throws -> String {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "AIUsageFixtures")
    )
    return try String(contentsOf: url, encoding: .utf8)
}

struct ClaudeUsageParserTests {
    @Test func readsBothWindows() throws {
        let usage = try #require(try ClaudeUsageParser.usage(Data(aiFixture("usage-latest.json").utf8)))

        #expect(usage.tool == .claudeCode)
        #expect(usage.windows.map(\.kind) == [.fiveHour, .week])
        #expect(usage.windows.map(\.used) == [0.43, 0.47])
        #expect(usage.windows[0].resetsAt == Date(timeIntervalSince1970: 1_793_751_600))
        #expect(usage.updatedAt == Date(timeIntervalSince1970: 1_793_749_122))
    }

    @Test func aMissingWindowIsLeftOut() throws {
        let data = Data(#"{"seven_day":{"used_percentage":47,"resets_at":1794225600}}"#.utf8)
        let usage = try #require(ClaudeUsageParser.usage(data))

        #expect(usage.windows.map(\.kind) == [.week])
    }

    @Test func notJSONIsNil() {
        #expect(ClaudeUsageParser.usage(Data("nope".utf8)) == nil)
    }
}

struct CodexUsageParserTests {
    @Test func takesTheLatestLimits() throws {
        let usage = try #require(try CodexUsageParser.usage(in: aiFixture("rollout.jsonl")))

        #expect(usage.tool == .codex)
        #expect(usage.updatedAt != nil)
    }

    @Test func tellsWindowsApartByLengthNotPosition() throws {
        let usage = try #require(try CodexUsageParser.usage(in: aiFixture("rollout.jsonl")))
        let windows = Dictionary(uniqueKeysWithValues: usage.windows.map { ("\($0.kind)", $0.used) })

        #expect(windows["fiveHour"] == 0.31)
        #expect(windows["week"] == 0.12)
        #expect(usage.windows.first?.kind == .fiveHour)
    }

    @Test func nullLimitsAreSkipped() {
        let line = #"{"timestamp":"2026-10-17T13:16:02.100Z","payload":{"type":"token_count","rate_limits":null}}"#
        #expect(CodexUsageParser.usage(in: line) == nil)
    }

    @Test func aPromptThatMentionsTheEventIsNotAnEvent() {
        let line = #"{"payload":{"type":"message","text":"token_count","rate_limits":{}}}"#
        #expect(CodexUsageParser.usage(in: line) == nil)
    }

    @Test func nothingOfTheConversationIsKept() throws {
        let usage = try #require(try CodexUsageParser.usage(in: aiFixture("rollout.jsonl")))
        #expect(!"\(usage)".contains("private"))
    }
}

struct AIUsageReadingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(_ used: Double, resetsIn seconds: TimeInterval, kind: AIWindow.Kind = .fiveHour) -> AIWindow {
        AIWindow(kind: kind, used: used, resetsAt: now.addingTimeInterval(seconds))
    }

    @Test func aWindowPastItsResetIsEmpty() {
        #expect(window(0.97, resetsIn: -1).used(at: now) == 0)
        #expect(window(0.97, resetsIn: 60).used(at: now) == 0.97)
    }

    @Test func peakIsTheHighestLiveWindowOfAnyTool() throws {
        let reading = AIUsageReading(
            tools: [
                AIToolUsage(
                    tool: .claudeCode,
                    windows: [window(0.43, resetsIn: 60), window(0.86, resetsIn: 60, kind: .week)]
                ),
                AIToolUsage(tool: .codex, windows: [window(0.99, resetsIn: -60)]),
            ],
            readAt: now
        )
        let peak = try #require(reading.peak(at: now))

        #expect(peak.tool == .claudeCode)
        #expect(peak.window.used == 0.86)
    }

    @Test func toolsWithoutWindowsHaveNoPeak() {
        let reading = AIUsageReading(tools: [AIToolUsage(tool: .droid)], readAt: now)
        #expect(reading.peak(at: now) == nil)
    }

    @Test func listsWhatIsNotInstalled() {
        let reading = AIUsageReading(tools: [AIToolUsage(tool: .codex)], readAt: now)

        #expect(reading.missing.count == 5)
        #expect(!reading.missing.contains(.codex))
    }
}

struct AIUsageCollectorTests {
    private func home(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func collector(_ home: URL, runner: FakeRunner? = nil, zstd: String? = nil) -> AIUsageCollector {
        let fallback = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") }
        return AIUsageCollector(runner: runner ?? fallback, home: home.path) { $0 == "zstd" ? zstd : nil }
    }

    @Test func findsOnlyWhatIsInstalled() async throws {
        let home = try home([".claude/usage-latest.json": aiFixture("usage-latest.json")])
        defer { try? FileManager.default.removeItem(at: home) }

        let reading = await collector(home).read()

        #expect(reading.tools.map(\.tool) == [.claudeCode])
        #expect(reading.tools[0].windows.count == 2)
    }

    @Test func aBareGeminiFolderIsNotTheCLI() async throws {
        let home = try home([".gemini/antigravity/x": ""])
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(await collector(home).read().tools.isEmpty)
    }

    @Test func toolsWithoutAKnownUsageFileShowNoUsage() async throws {
        let home = try home([".copilot/config.json": "{}", ".factory/x": ""])
        defer { try? FileManager.default.removeItem(at: home) }

        let tools = await collector(home).read().tools

        #expect(tools.map(\.tool) == [.copilotCLI, .droid])
        #expect(tools.allSatisfy { $0.windows.isEmpty && !$0.isUnreadable })
    }

    @Test func aBrokenUsageFileIsUnreadable() async throws {
        let home = try home([".claude/usage-latest.json": "not json"])
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(await collector(home).read().tools.first?.isUnreadable == true)
    }

    @Test func readsAPlainSessionLog() async throws {
        let log = try aiFixture("rollout.jsonl")
        let home = try home([".codex/sessions/2026/10/17/rollout-2026-10-17T16-15-21-a.jsonl": log])
        defer { try? FileManager.default.removeItem(at: home) }

        let usage = await collector(home).read().tools.first

        #expect(usage?.tool == .codex)
        #expect(usage?.windows.count == 2)
    }

    @Test func decompressesLogsWithZstd() async throws {
        let log = try aiFixture("rollout.jsonl")
        let home = try home([".codex/sessions/2026/10/17/rollout-2026-10-17T16-15-21-a.jsonl.zst": "compressed"])
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: log, stderr: "") }

        let usage = await collector(home, runner: runner, zstd: "/opt/homebrew/bin/zstd").read().tools.first

        #expect(usage?.windows.count == 2)
        #expect(runner.calls.first?.prefix(3) == ["/opt/homebrew/bin/zstd", "-dc", "--"])
    }

    @Test func withoutZstdCompressedLogsAreUnreadable() async throws {
        let home = try home([".codex/sessions/2026/10/17/rollout-2026-10-17T16-15-21-a.jsonl.zst": "compressed"])
        defer { try? FileManager.default.removeItem(at: home) }

        let usage = await collector(home).read().tools.first

        #expect(usage?.isUnreadable == true)
    }

    @Test func looksFurtherBackWhenTheNewestLogHasNoLimits() async throws {
        let log = try aiFixture("rollout.jsonl")
        let home = try home([
            ".codex/sessions/2026/10/18/rollout-2026-10-18T09-00-00-b.jsonl": "{}",
            ".codex/sessions/2026/10/17/rollout-2026-10-17T16-15-21-a.jsonl": log,
        ])
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(await collector(home).read().tools.first?.windows.count == 2)
    }

    @Test func newestLogsComeFirstAndOtherFilesAreIgnored() throws {
        let home = try home([
            ".codex/sessions/2025/12/01/rollout-2025-12-01T09-00-00-a.jsonl": "",
            ".codex/sessions/2026/01/02/rollout-2026-01-02T09-00-00-b.jsonl.zst": "",
            ".codex/sessions/2026/01/02/notes.txt": "",
        ])
        defer { try? FileManager.default.removeItem(at: home) }

        let logs = AIUsageCollector.newestLogs(in: home.appending(path: ".codex/sessions"), limit: 5)

        #expect(logs.map { String($0.lastPathComponent.prefix(18)) } == ["rollout-2026-01-02", "rollout-2025-12-01"])
    }

    @Test func loginFilesAreNeverOpened() async throws {
        // Unreadable on purpose: reading it would make the tool look broken.
        let home = try home([
            ".codex/sessions/2026/10/17/rollout-2026-10-17T16-15-21-a.jsonl": "{}",
            ".codex/auth.json": "{",
        ])
        defer { try? FileManager.default.removeItem(at: home) }

        let usage = await collector(home).read().tools.first

        #expect(usage?.isUnreadable == false)
        #expect(usage?.windows.isEmpty == true)
    }

    @Test func theSeamCanReplaceLocalNumbers() async throws {
        struct Exact: AILimitProvider {
            func refined(_ usage: AIToolUsage) async -> AIToolUsage {
                AIToolUsage(tool: usage.tool, windows: [AIWindow(kind: .week, used: 0.5, resetsAt: nil)])
            }
        }
        let home = try home([".factory/x": ""])
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: "", stderr: "") }
        let collector = AIUsageCollector(runner: runner, home: home.path, limits: Exact()) { _ in nil }

        #expect(await collector.read().tools.first?.windows.first?.used == 0.5)
    }
}

struct AIRefreshOptionTests {
    @Test func defaultsToFiveMinutes() {
        #expect(DeveloperOptions().aiRefreshMinutes == 5)
    }

    @Test(arguments: [("15", 15), ("0", 5), ("-3", 5), ("soon", 5), ("9999", 5)])
    func readsTheInterval(text: String, minutes: Int) {
        var settings = AppSettings()
        settings.update(.aiUsage) { $0.options[DeveloperOptions.Key.refreshMinutes] = text }

        #expect(DeveloperOptions(settings: settings).aiRefreshMinutes == minutes)
    }
}
