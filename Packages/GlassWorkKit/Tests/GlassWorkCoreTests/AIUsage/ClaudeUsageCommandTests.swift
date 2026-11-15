import Foundation
@testable import GlassWorkCore
import Testing

private func fixtureText(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "AIUsageFixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

/// `2026-11-16 03:20 +0300` and the like.
private func moscow(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm Z"
    return formatter.date(from: text + " +0300")!
}

private func output(_ result: String, turns: Int = 0, cost: Double = 0) -> String {
    let text = result.replacing("\n", with: "\\n")
    return #"{"type":"result","num_turns":\#(turns),"total_cost_usd":\#(cost),"result":"\#(text)"}"#
}

struct ClaudeUsageCommandTests {
    private func usage(_ result: ClaudeUsageCommand.Result) throws -> AIToolUsage {
        guard case let .usage(usage) = result else {
            Issue.record("expected usage, got \(result)")
            throw CancellationError()
        }
        return usage
    }

    @Test func readsSessionAndWeekFromARealCapture() throws {
        let now = moscow("2026-11-16 01:14")
        let result = try usage(ClaudeUsageCommand.parse(fixtureText("claude-usage.json"), now: now))
        #expect(result.tool == .claudeCode)
        #expect(result.source == .tool)
        #expect(result.updatedAt == now)
        #expect(result.windows.map(\.kind) == [.fiveHour, .week])
        #expect(result.windows.map(\.used) == [0.47, 0.43])
        #expect(result.windows.map(\.resetsAt) == [moscow("2026-11-16 03:20"), moscow("2026-11-16 14:59")])
    }

    @Test func hourWithoutMinutesAndTimeWithoutDate() throws {
        let now = moscow("2026-11-16 21:00")
        let result = try usage(ClaudeUsageCommand.parse(fixtureText("claude-usage-no-minutes-handmade.json"), now: now))
        #expect(result.windows.map(\.used) == [0.12, 0.05])
        // `3pm` on the 16th has passed, but a dated reset is taken as written.
        #expect(result.windows[0].resetsAt == moscow("2026-11-16 15:00"))
        // `8:10pm` without a date is past today, so it is tomorrow.
        #expect(result.windows[1].resetsAt == moscow("2026-11-17 20:10"))
    }

    @Test func aJanuaryResetSeenInDecemberIsNextYear() throws {
        let now = moscow("2026-12-30 12:00")
        let line = "Current session: 1% used · resets Jan 2 at 9am (Europe/Moscow)"
        let window = try #require(ClaudeUsageCommand.window(line, now: now))
        #expect(window.resetsAt == moscow("2027-01-02 09:00"))
    }

    @Test func aDecemberResetSeenInJanuaryIsNotNextDecember() throws {
        let now = moscow("2027-01-01 00:30")
        let line = "Current week (all models): 99% used · resets Dec 31 at 11pm (Europe/Moscow)"
        let window = try #require(ClaudeUsageCommand.window(line, now: now))
        #expect(window.resetsAt == moscow("2026-12-31 23:00"))
    }

    @Test func unknownTimeZoneKeepsThePercent() throws {
        let line = "Current session: 30% used · resets Nov 16 at 3pm (Mars/Base)"
        let window = try #require(ClaudeUsageCommand.window(line, now: Date()))
        #expect(window.used == 0.3)
        #expect(window.resetsAt == nil)
    }

    @Test func aModelLineIsNotTheOverallLimit() {
        #expect(ClaudeUsageCommand.window("Current week (Fable): 27% used · resets Nov 16 at 3pm (UTC)", now: Date())
            == nil)
    }

    @Test func aTurnMeansTheCommandReachedTheModel() {
        #expect(ClaudeUsageCommand.parse(output("Current session: 1% used", turns: 1), now: Date()) == .spentTurns)
    }

    @Test func aCostMeansTheCommandReachedTheModel() {
        #expect(ClaudeUsageCommand.parse(output("Current session: 1% used", cost: 0.01), now: Date()) == .spentTurns)
    }

    @Test func textWithoutLimitLinesIsUnreadable() {
        #expect(ClaudeUsageCommand.parse(output("Not logged in"), now: Date()) == .unreadable)
        #expect(ClaudeUsageCommand.parse("not json", now: Date()) == .unreadable)
        #expect(ClaudeUsageCommand.parse("{}", now: Date()) == .unreadable)
    }
}
