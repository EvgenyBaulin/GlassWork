import Foundation
@testable import GlassWorkCore
import Testing

struct AIUsageOptionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ tools: [AIToolUsage]) -> AIUsageReading {
        AIUsageReading(tools: tools, readAt: now)
    }

    private var both: AIUsageReading {
        reading([
            AIToolUsage(tool: .codex, windows: [
                AIWindow(kind: .fiveHour, used: 0.2, resetsAt: nil),
                AIWindow(kind: .week, used: 0.7, resetsAt: nil),
            ]),
            AIToolUsage(tool: .claudeCode, windows: [
                AIWindow(kind: .fiveHour, used: 0.4, resetsAt: nil),
                AIWindow(kind: .week, used: 0.1, resetsAt: nil),
            ]),
        ])
    }

    @Test
    func highestLooksAtEveryWindow() {
        #expect(both.peak(at: now, choice: .highest)?.window.used == 0.7)
    }

    @Test
    func oneWindowComparesToolsWithinIt() {
        let peak = both.peak(at: now, choice: .fiveHour)
        #expect(peak?.tool == .claudeCode)
        #expect(peak?.window.used == 0.4)
    }

    @Test
    func aToolWithoutThatWindowStillShowsSomething() {
        let weekly = reading([AIToolUsage(tool: .codex, windows: [AIWindow(kind: .week, used: 0.3, resetsAt: nil)])])
        #expect(weekly.peak(at: now, choice: .fiveHour)?.window.kind == .week)
    }

    @Test
    func theWarningStartsAtTheDefault() {
        #expect(both.warnLevel == AIUsageReading.alertShare)
    }

    @Test
    func settingsMoveTheWarning() {
        #expect(both.warning(at: 0.6).warnLevel == 0.6)
    }

    @Test
    func theLevelSurvivesTheTripToWidgets() throws {
        let data = try JSONEncoder().encode(both.warning(at: 0.6))
        let decoded = try JSONDecoder().decode(AIUsageReading.self, from: data)
        #expect(decoded.warnLevel == 0.6)
    }

    @Test
    func aHandEditStaysInRange() {
        #expect(AIUsageOption.warnShare([AIUsageOption.warnPercent: "500"]) == 1)
        #expect(AIUsageOption.warnShare([:]) == 0.9)
    }
}
