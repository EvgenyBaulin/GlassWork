import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Tool names may appear only in this folder, so these snapshots live apart from the other widgets.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AIUsageWidgetTests {
    private var sample: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.aiUsage = AIUsageReading(
            tools: [
                AIToolUsage(
                    tool: .claudeCode,
                    windows: [
                        AIWindow(kind: .fiveHour, used: 0.43, resetsAt: sampleNow.addingTimeInterval(4920)),
                        AIWindow(kind: .week, used: 0.86, resetsAt: sampleNow.addingTimeInterval(320_000)),
                    ],
                    updatedAt: sampleNow.addingTimeInterval(-30)
                ),
                AIToolUsage(
                    tool: .codex,
                    windows: [
                        AIWindow(kind: .fiveHour, used: 0.12, resetsAt: sampleNow.addingTimeInterval(9900)),
                        AIWindow(kind: .week, used: 0.31, resetsAt: sampleNow.addingTimeInterval(400_000)),
                    ],
                    updatedAt: sampleNow.addingTimeInterval(-1500)
                ),
                AIToolUsage(tool: .geminiCLI),
            ],
            readAt: sampleNow
        )
        return snapshot
    }

    @Test func rendersEverySizeInBothAppearances() {
        for size in WidgetSize.allCases {
            for dark in [true, false] {
                widgetSnapshot(
                    WidgetFace(kind: .aiUsage, size: size, snapshot: sample, now: sampleNow),
                    size: size,
                    dark: dark,
                    named: "\(size.rawValue)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    @Test func limitReached() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.aiUsage = AIUsageReading(
            tools: [AIToolUsage(
                tool: .claudeCode,
                windows: [AIWindow(kind: .fiveHour, used: 1, resetsAt: sampleNow.addingTimeInterval(3000))]
            )],
            readAt: sampleNow
        )
        widgetSnapshot(
            WidgetFace(kind: .aiUsage, size: .small, snapshot: snapshot, now: sampleNow),
            size: .small,
            dark: true,
            named: "limit"
        )
    }

    @Test func waitsForItsFirstReading() {
        widgetSnapshot(
            WidgetFace(kind: .aiUsage, size: .small, snapshot: WidgetSnapshot(date: sampleNow), now: sampleNow),
            size: .small,
            dark: true,
            named: "waiting"
        )
    }

    @Test func noToolsFound() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.aiUsage = AIUsageReading(tools: [], readAt: sampleNow)
        widgetSnapshot(
            WidgetFace(kind: .aiUsage, size: .medium, snapshot: snapshot, now: sampleNow),
            size: .medium,
            dark: true,
            named: "empty"
        )
    }
}
