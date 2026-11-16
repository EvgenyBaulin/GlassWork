import Foundation
@testable import GlassWorkCore
import Testing

/// The shape of `gh api /copilot_internal/user`, with made-up values and the identity fields kept only to
/// show they are ignored.
private func answer(chat: String, premium: String) -> String {
    #"""
    {"login":"someone","id":1,"copilot_plan":"individual",
     "quota_snapshots":{"chat":\#(chat),"premium_interactions":\#(premium),
       "completions":{"entitlement":2000,"percent_remaining":100.0,"unlimited":false,"has_quota":true}},
     "quota_reset_date":"2026-12-01","quota_reset_date_utc":"2026-12-01T00:00:00.000Z"}
    """#
}

private let limitedChat = #"{"entitlement":200,"percent_remaining":80.8,"unlimited":false,"has_quota":true}"#
private let noPremium = #"{"entitlement":0,"percent_remaining":0.0,"unlimited":false,"has_quota":false}"#
private let unlimitedChat = #"{"entitlement":0,"percent_remaining":100.0,"unlimited":true,"has_quota":true}"#
private let limitedPremium = #"{"entitlement":300,"percent_remaining":25.0,"unlimited":false,"has_quota":true}"#

struct CopilotQuotaTests {
    private let reset = Date(timeIntervalSince1970: 1_796_083_200) // 2026-12-01 00:00 UTC

    @Test func freePlanCountsChatCredits() throws {
        let window = try #require(CopilotQuota.window(from: answer(chat: limitedChat, premium: noPremium)))

        #expect(window.kind == .month)
        #expect(abs(window.used - 0.192) < 0.0001)
        #expect(window.resetsAt == reset)
    }

    @Test func paidPlanCountsPremiumRequests() throws {
        let window = try #require(CopilotQuota.window(from: answer(chat: unlimitedChat, premium: limitedPremium)))

        #expect(window.used == 0.75)
    }

    @Test func noLimitMeansNoWindow() {
        #expect(CopilotQuota.window(from: answer(chat: unlimitedChat, premium: noPremium)) == nil)
        #expect(CopilotQuota.window(from: #"{"message":"Not Found","status":"404"}"#) == nil)
        #expect(CopilotQuota.window(from: "not json") == nil)
    }

    @Test func collectorAddsThePlanLimitToTheSpend() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appending(path: ".copilot"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner { _, _ in
            ProcessOutput(status: 0, stdout: answer(chat: limitedChat, premium: noPremium), stderr: "")
        }
        let now = Date(timeIntervalSince1970: 1_794_850_000)
        let collector = AIUsageCollector(runner: runner, home: home.path) { $0 == "gh" ? "/opt/gh" : nil }

        let usage = try #require(await collector.read(at: now).tools.first { $0.tool == .copilotCLI })

        #expect(usage.windows.map(\.kind) == [.month])
        #expect(usage.source == .tool)
        #expect(usage.updatedAt == now)
        #expect(runner.calls == [["/opt/gh", "api", "/copilot_internal/user"]])
    }

    @Test func aFailedRequestLeavesTheSpendAlone() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appending(path: ".copilot"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "HTTP 401") }
        let collector = AIUsageCollector(runner: runner, home: home.path) { $0 == "gh" ? "/opt/gh" : nil }

        let usage = try #require(await collector.read().tools.first { $0.tool == .copilotCLI })

        #expect(usage.windows.isEmpty)
        #expect(usage.source == .files)
    }
}
