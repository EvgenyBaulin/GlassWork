import Foundation
@testable import GlassWorkCore
import Testing

struct CodexAppServerTests {
    private func lines() throws -> [String] {
        let url = try #require(Bundle.module.url(
            forResource: "codex-rate-limits.jsonl",
            withExtension: nil,
            subdirectory: "AIUsageFixtures"
        ))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test func readsBothWindowsFromARealAnswer() throws {
        let answer = try #require(lines().first(where: CodexAppServer.isAnswer))
        let now = Date(timeIntervalSince1970: 1_794_780_896)
        let usage = try #require(CodexAppServer.usage(fromAnswer: answer, now: now))
        #expect(usage.tool == .codex)
        #expect(usage.source == .tool)
        #expect(usage.updatedAt == now)
        #expect(usage.windows.map(\.kind) == [.fiveHour, .week])
        #expect(usage.windows.map(\.used) == [1.0, 0.18])
        #expect(usage.windows.map(\.resetsAt) == [
            Date(timeIntervalSince1970: 1_794_789_742), Date(timeIntervalSince1970: 1_795_252_304),
        ])
    }

    @Test func answerDetectionIgnoresTheOtherLines() throws {
        let all = try lines()
        #expect(all.count(where: CodexAppServer.isAnswer) == 1)
        #expect(!CodexAppServer.isAnswer(#"{"method":"account/rateLimits/updated","params":{"id":2}}"#))
        #expect(!CodexAppServer.isAnswer("not json"))
    }

    @Test func anErrorAnswerIsNil() {
        let line = #"{"id":2,"error":{"code":-32600,"message":"not logged in"}}"#
        #expect(CodexAppServer.usage(fromAnswer: line, now: Date()) == nil)
    }

    @Test func requestsAreThreeLinesEndingWithTheLimitsRequest() throws {
        let requests = CodexAppServer.requests(clientVersion: "0.1.0")
        #expect(requests.count == 3)
        #expect(requests[0].contains(#""clientInfo":{"name":"GlassWork","version":"0.1.0"}"#))
        #expect(requests[1].contains(#""method":"initialized""#))
        #expect(try CodexAppServer.isAnswer(#require(requests.last)))
        #expect(requests[2].contains("account/rateLimits/read"))
    }
}
