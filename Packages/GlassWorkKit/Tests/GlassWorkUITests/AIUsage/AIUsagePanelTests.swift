import Foundation
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func window(_ used: Double, resetsIn seconds: TimeInterval, kind: AIWindow.Kind = .fiveHour) -> AIWindow {
    AIWindow(kind: kind, used: used, resetsAt: now.addingTimeInterval(seconds))
}

private var sample: AIUsageReading {
    AIUsageReading(
        tools: [
            AIToolUsage(
                tool: .claudeCode,
                windows: [window(0.43, resetsIn: 8040), window(0.92, resetsIn: 260_000, kind: .week)],
                updatedAt: now.addingTimeInterval(-40)
            ),
            AIToolUsage(
                tool: .codex,
                windows: [window(0.12, resetsIn: 13200), window(0.31, resetsIn: 180_000, kind: .week)],
                updatedAt: now.addingTimeInterval(-1500)
            ),
            AIToolUsage(tool: .geminiCLI),
        ],
        readAt: now.addingTimeInterval(-120)
    )
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AIUsagePanelSnapshotTests {
    @Test(arguments: [true, false])
    func panel(dark: Bool) {
        snapshotPanel(AIUsagePanel(reading: sample, refreshMinutes: 5, now: now), name: "ai-usage", dark: dark)
    }

    @Test func noToolsFound() {
        let reading = AIUsageReading(tools: [], readAt: now)
        snapshotPanel(AIUsagePanel(reading: reading, refreshMinutes: 5, now: now), name: "ai-usage-none")
    }

    @Test func unreadable() {
        let reading = AIUsageReading(tools: [AIToolUsage(tool: .codex, isUnreadable: true)], readAt: now)
        snapshotPanel(AIUsagePanel(reading: reading, refreshMinutes: 5, now: now), name: "ai-usage-error")
    }
}

@MainActor
struct AIUsageItemTests {
    @Test func showsTheHighestShare() {
        let reading = AIUsageReading(
            tools: [AIToolUsage(tool: .claudeCode, windows: [window(0.43, resetsIn: 60)])],
            readAt: now
        )
        let item = ItemContent.aiUsage(reading, at: now)

        #expect(item.figure == "43%")
        #expect(item.alert == nil)
        #expect(item.glyph == .ring(0.43))
        #expect(item.detail?.hasPrefix("Claude Code 43%") == true)
    }

    @Test(arguments: [(0.89, false), (0.9, true), (0.97, true)])
    func turnsOrangeAtNinetyPercent(share: Double, isOrange: Bool) {
        let reading = AIUsageReading(
            tools: [AIToolUsage(tool: .codex, windows: [window(share, resetsIn: 60)])],
            readAt: now
        )
        #expect((ItemContent.aiUsage(reading, at: now).alert == Palette.orange) == isOrange)
    }

    @Test func aWindowThatHasResetIsNotAnAlert() {
        let reading = AIUsageReading(
            tools: [AIToolUsage(tool: .codex, windows: [window(0.97, resetsIn: -60)])],
            readAt: now
        )
        let item = ItemContent.aiUsage(reading, at: now)

        #expect(item.figure == "0%")
        #expect(item.alert == nil)
    }

    @Test func noUsageIsFaint() {
        let item = ItemContent.aiUsage(AIUsageReading(tools: [], readAt: now), at: now)

        #expect(item.figure == "—")
        #expect(item.isDimmed)
    }
}
