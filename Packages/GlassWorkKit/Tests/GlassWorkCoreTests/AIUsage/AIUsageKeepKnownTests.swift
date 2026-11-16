import Foundation
@testable import GlassWorkCore
import Testing

struct AIUsageKeepKnownTests {
    private let earlier = Date(timeIntervalSince1970: 1_794_850_000)
    private let now = Date(timeIntervalSince1970: 1_794_853_000)

    private func limits(_ tool: AITool, used: Double) -> AIToolUsage {
        AIToolUsage(
            tool: tool,
            windows: [AIWindow(kind: .fiveHour, used: used, resetsAt: nil)],
            updatedAt: earlier
        )
    }

    @Test func anUnreadableToolKeepsItsLastNumbers() {
        let previous = AIUsageReading(tools: [limits(.claudeCode, used: 0.4)], readAt: earlier)
        let fresh = AIUsageReading(tools: [AIToolUsage(tool: .claudeCode, isUnreadable: true)], readAt: now)

        let shown = fresh.keepingKnown(from: previous)

        #expect(shown.tools == previous.tools)
        #expect(shown.readAt == now)
    }

    @Test func aReadThatFindsNothingKeepsTheLastNumbers() {
        let previous = AIUsageReading(tools: [limits(.codex, used: 0.34)], readAt: earlier)
        let fresh = AIUsageReading(tools: [AIToolUsage(tool: .codex)], readAt: now)

        #expect(fresh.keepingKnown(from: previous).tools == previous.tools)
    }

    @Test func newNumbersReplaceOldOnes() {
        let previous = AIUsageReading(tools: [limits(.codex, used: 0.34)], readAt: earlier)
        let fresh = AIUsageReading(tools: [limits(.codex, used: 0.5)], readAt: now)

        #expect(fresh.keepingKnown(from: previous).tools == fresh.tools)
    }

    @Test func withoutEarlierNumbersTheFailureShows() {
        let previous = AIUsageReading(tools: [AIToolUsage(tool: .claudeCode, isUnreadable: true)], readAt: earlier)
        let fresh = AIUsageReading(tools: [AIToolUsage(tool: .claudeCode, isUnreadable: true)], readAt: now)

        #expect(fresh.keepingKnown(from: previous).tools.first?.isUnreadable == true)
        #expect(fresh.keepingKnown(from: nil) == fresh)
    }

    @Test func keptSpendCountsAsNumbers() {
        let spend = AISpend(today: AISpendTotals(aiCredits: 2), last7Days: AISpendTotals(), month: AISpendTotals())
        let previous = AIUsageReading(tools: [AIToolUsage(tool: .copilotCLI, spend: spend)], readAt: earlier)
        let fresh = AIUsageReading(tools: [AIToolUsage(tool: .copilotCLI, isUnreadable: true)], readAt: now)

        #expect(fresh.keepingKnown(from: previous).tools.first?.spend == spend)
    }

    @Test func aToolThatWentAwayIsNotBroughtBack() {
        let previous = AIUsageReading(
            tools: [limits(.codex, used: 0.34), limits(.claudeCode, used: 0.1)],
            readAt: earlier
        )
        let fresh = AIUsageReading(tools: [limits(.claudeCode, used: 0.2)], readAt: now)

        #expect(fresh.keepingKnown(from: previous).tools.map(\.tool) == [.claudeCode])
    }

    @Test func theWarningLevelStays() {
        let fresh = AIUsageReading(tools: [], readAt: now).warning(at: 0.75)

        #expect(fresh.keepingKnown(from: AIUsageReading(tools: [], readAt: earlier)).warnLevel == 0.75)
    }

    @MainActor
    @Test func theSavedReadingFillsOnlyAnEmptyStore() {
        let store = DeveloperStore()
        let saved = AIUsageReading(tools: [limits(.codex, used: 0.34)], readAt: earlier)

        store.restore(aiUsage: saved)
        store.restore(aiUsage: AIUsageReading(tools: [], readAt: now))

        #expect(store.aiUsage?.tools == saved.tools)
    }
}
