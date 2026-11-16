import Foundation
@testable import GlassWorkCore
import Testing

private func fixture() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "events", withExtension: "jsonl", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

private func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
    return value
}

private func record(
    at timestamp: String?,
    credits: Double = 1,
    requests: Double = 1,
    model: String = "model-a"
) -> String {
    let time = timestamp.map { ",\"timestamp\":\"\($0)\"" } ?? ""
    return """
    {"type":"session.usage_record"\(time),"data":{"usage":{"model":"\(model)",\
    "inputTokens":100,"outputTokens":10,"cacheReadTokens":50,"cost":\(requests),\
    "copilotUsage":{"totalNanoAiu":\(credits * 1_000_000_000)}}}}
    """
}

struct CopilotUsageParserTests {
    private let modifiedAt = date("2026-11-16T12:00:00Z")

    @Test func finalSnapshotOverridesRecordsAndCheckpoint() throws {
        let session = try #require(try CopilotUsageParser.parse(fixture(), modifiedAt: modifiedAt))
        #expect(session.startDate == date("2026-11-16T06:00:00Z"))
        #expect(session.updatedAt == date("2026-11-16T06:04:00Z"))
        #expect(session.totals == AISpendTotals(
            aiCredits: 12.4, premiumRequests: 3, inputTokens: 5000, outputTokens: 500, cachedTokens: 2500
        ))
        #expect(session.models.map(\.model) == ["model-b", "model-a"])
        #expect(session.models.first?.displayName == "Model B")
        #expect(session.models.first?.totals.aiCredits == 10.4)
    }

    @Test func sumsRecordsWithoutSnapshots() throws {
        let text = try fixture().split(separator: "\n").filter {
            !$0.contains("session.shutdown") && !$0.contains("session.usage_checkpoint")
        }.joined(separator: "\n")
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: modifiedAt))
        #expect(session.totals == AISpendTotals(
            aiCredits: 5, premiumRequests: 4, inputTokens: 3000, outputTokens: 300, cachedTokens: 1500
        ))
        #expect(session.models.count == 2)
    }

    @Test func checkpointAndLaterCallsAreNotDoubleCounted() throws {
        let text = try fixture().split(separator: "\n").filter { !$0.contains("session.shutdown") }
            .joined(separator: "\n")
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: modifiedAt))
        #expect(session.totals.aiCredits == 5)
        #expect(session.totals.premiumRequests == 3)
        #expect(session.totals.inputTokens == 3000)
    }

    @Test func resumedSessionIncludesCallsAfterShutdown() throws {
        let text = try fixture() + "\n" + record(at: "2026-11-16T07:00:00Z", credits: 2)
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: modifiedAt))
        #expect(session.totals.aiCredits == 14.4)
        #expect(session.totals.premiumRequests == 4)
    }

    @Test func malformedLinesAreSkippedAndMessageDataIsNeverDecoded() throws {
        let text = """
        not json
        {"type":"session.usage_record","data":{"usage":{"inputTokens":"broken"}}}
        {"type":"user.message","data":{"usage":{"model":"fake","cost":999999}}}
        {"type":"assistant.message","data":"session.usage_record"}
        {"type":"tool.execution_complete","data":null}
        \(record(at: "2026-11-16T06:01:00Z"))
        {"type":"session.shutdown","data":{"accountingSnapshot":"broken"}}
        {"type":
        """
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: modifiedAt))
        #expect(session.totals.aiCredits == 1)
        #expect(session.totals.premiumRequests == 1)
        #expect(session.models.map(\.model) == ["model-a"])
    }

    @Test func timestampFallsBackToSessionStartThenModificationDate() throws {
        let start = #"{"type":"session.start","data":{"startTime":"2026-11-15T09:00:00Z"}}"#
        let withStart = try #require(CopilotUsageParser.parse(start + "\n" + record(at: nil), modifiedAt: modifiedAt))
        #expect(withStart.updatedAt == date("2026-11-15T09:00:00Z"))
        let withoutStart = try #require(CopilotUsageParser.parse(record(at: nil), modifiedAt: modifiedAt))
        #expect(withoutStart.startDate == modifiedAt)
        #expect(withoutStart.updatedAt == modifiedAt)
    }

    @Test func premiumRequestsWorkWithoutCreditsAndMissingTokenCounters() throws {
        let text = #"{"type":"session.usage_record","data":{"usage":{"model":"model-a","cost":0.5}}}"#
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: modifiedAt))
        #expect(session.totals == AISpendTotals(premiumRequests: 0.5))
    }

    @Test func noAccountingReturnsNil() {
        #expect(CopilotUsageParser.parse(#"{"type":"user.message","data":{}}"#, modifiedAt: modifiedAt) == nil)
    }

    @Test func oldSnapshotsWithoutSpendStillDecode() throws {
        let text = #"{"tools":[{"tool":"copilotCLI","windows":[],"isUnreadable":false}],"readAt":0}"#
        let reading = try JSONDecoder().decode(AIUsageReading.self, from: Data(text.utf8))
        #expect(reading.tools.first?.spend == nil)
    }

    @Test func spendRoundTripsInSnapshots() throws {
        let spend = AISpend(
            today: AISpendTotals(aiCredits: 1),
            last7Days: AISpendTotals(aiCredits: 2),
            month: AISpendTotals(aiCredits: 3)
        )
        let usage = AIToolUsage(tool: .copilotCLI, source: .files, spend: spend)
        #expect(try JSONDecoder().decode(AIToolUsage.self, from: JSONEncoder().encode(usage)) == usage)
    }
}

struct CopilotUsageAggregationTests {
    private let now = date("2026-11-02T09:00:00Z")

    @Test func calendarDaysAndMonthUseTheGivenTimeZone() throws {
        let text = [
            record(at: "2026-11-01T21:00:00Z", credits: 1), // Today at midnight locally.
            record(at: "2026-11-01T20:59:59Z", credits: 2),
            record(at: "2026-10-31T21:00:00Z", credits: 4), // First of the month locally.
            record(at: "2026-10-31T20:59:59Z", credits: 8),
            record(at: "2026-10-26T21:00:00Z", credits: 16), // Beginning of the seven calendar days.
            record(at: "2026-10-26T20:59:59Z", credits: 32),
            record(at: "2026-11-02T10:00:00Z", credits: 64), // Future events are excluded.
        ].joined(separator: "\n")
        let session = try #require(CopilotUsageParser.parse(text, modifiedAt: now))
        let spend = CopilotUsageReader.aggregate([session], at: now, calendar: calendar)
        #expect(spend.today.aiCredits == 1)
        #expect(spend.last7Days.aiCredits == 31)
        #expect(spend.month.aiCredits == 7)
        #expect(spend.today.premiumRequests == 1)
        #expect(spend.last7Days.premiumRequests == 5)
        #expect(spend.month.premiumRequests == 3)
        #expect(spend.month.inputTokens == 300)
    }

    @Test func mergesAndRanksModelsAcrossSessions() throws {
        let first = try #require(CopilotUsageParser.parse(record(at: nil, credits: 2), modifiedAt: now))
        let second = try #require(CopilotUsageParser.parse(record(at: nil, credits: 3), modifiedAt: now))
        let third = try #require(CopilotUsageParser.parse(
            record(at: nil, credits: 4, model: "model-b"),
            modifiedAt: now
        ))
        let spend = CopilotUsageReader.aggregate([third, second, first], at: now, calendar: calendar)
        #expect(spend.topModels.map(\.model) == ["model-a", "model-b"])
        #expect(spend.topModels.first?.totals.aiCredits == 5)
    }
}

struct CopilotUsageReaderTests {
    private let now = date("2026-11-16T12:00:00Z")

    private func session(in home: URL, text: String, modifiedAt: Date) throws -> URL {
        let file = home.appending(path: ".copilot/session-state/\(UUID().uuidString)/events.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        return file
    }

    @Test func collectorReadsOnlyRecentBoundedSessionFiles() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try session(in: home, text: record(at: nil, credits: 2), modifiedAt: now)
        // A recent event in an old file must still be ignored by modification date.
        _ = try session(
            in: home,
            text: record(at: "2026-11-16T06:00:00Z", credits: 999),
            modifiedAt: #require(calendar.date(byAdding: .day, value: -32, to: now))
        )
        let large = try session(in: home, text: record(at: nil, credits: 999), modifiedAt: now)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: 16 * 1024 * 1024 + 1)
        try handle.close()
        // Neither configuration nor logs are candidate usage files.
        let config = home.appending(path: ".copilot/config.json")
        try record(at: nil, credits: 999).write(to: config, atomically: true, encoding: .utf8)
        let logs = home.appending(path: ".copilot/logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try record(at: nil, credits: 999).write(
            to: logs.appending(path: "events.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        let link = try session(in: home, text: "", modifiedAt: now)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: config)
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") }
        let collector = AIUsageCollector(runner: runner, home: home.path) { _ in nil }
        let reading = await collector.read(at: now, calendar: calendar)
        let usage = try #require(reading.tools.first)
        #expect(usage.tool == .copilotCLI)
        #expect(usage.windows.isEmpty)
        #expect(usage.source == .files)
        #expect(!usage.isUnreadable)
        #expect(usage.spend?.today.aiCredits == 2)
        #expect(usage.spend?.last7Days.aiCredits == 2)
        #expect(usage.spend?.month.aiCredits == 2)
        #expect(runner.calls.isEmpty)
    }

    @Test func modificationCutoffIsInclusive() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let cutoff = try #require(calendar.date(byAdding: .day, value: -31, to: now))
        _ = try session(in: home, text: record(at: "2026-11-16T06:00:00Z", credits: 3), modifiedAt: cutoff)
        _ = try session(
            in: home,
            text: record(at: "2026-11-16T06:00:00Z", credits: 999),
            modifiedAt: cutoff.addingTimeInterval(-1)
        )
        #expect(CopilotUsageReader.read(home: home, at: now, calendar: calendar).spend?.today.aiCredits == 3)
    }
}
