import Foundation
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func usage(_ tool: AITool, _ used: Double) -> AIToolUsage {
    AIToolUsage(
        tool: tool,
        windows: [AIWindow(kind: .fiveHour, used: used, resetsAt: now.addingTimeInterval(3600))],
        updatedAt: now.addingTimeInterval(-60)
    )
}

private var sample: AIUsageReading {
    AIUsageReading(tools: [usage(.claudeCode, 0.43), usage(.codex, 0.12)], readAt: now.addingTimeInterval(-120))
}

@MainActor
struct AIUsageToolChoiceTests {
    private let window = [AIUsageOption.window: AIUsageWindowChoice.highest.rawValue]

    @Test func highestIsTheDefault() {
        let item = ItemContent.aiUsage(sample, at: now, options: window)

        #expect(item.figure == "43%")
    }

    @Test func aChosenToolFeedsTheMenuBar() {
        let options = window.merging([AIUsageOption.menuBarTool: AITool.codex.rawValue]) { $1 }
        let item = ItemContent.aiUsage(sample, at: now, options: options)

        #expect(item.figure == "12%")
        #expect(item.detail?.hasPrefix(AITool.codex.title) == true)
    }

    @Test func aChosenToolThatIsNotThereShowsADash() {
        let options = [AIUsageOption.menuBarTool: AITool.droid.rawValue]

        #expect(ItemContent.aiUsage(sample, at: now, options: options).figure == "—")
    }

    @Test func everyToolHasACheckboxAndAChoice() {
        let rows = ModuleOptionSpec.usageRows
        let keys = Set(rows.map(\.key))

        #expect(keys.contains(AIUsageOption.menuBarTool))
        for tool in AITool.allCases {
            #expect(keys.contains(AIUsageOption.enabledKey(tool)))
        }
        guard case let .choice(choices) = rows.first(where: { $0.key == AIUsageOption.menuBarTool })?.kind else {
            Issue.record("the menu bar tool is not a choice")
            return
        }
        #expect(choices.first?.value == AIUsageOption.highestTool)
        #expect(choices.count == AITool.allCases.count + 1)
    }

    @Test func aToolToggleWritesAndRemovesItsOption() {
        var settings = AppSettings()
        let row = ModuleOptionSpec.usageRows.first { $0.key == AIUsageOption.enabledKey(.codex) }

        row?.write(&settings, "false")
        #expect(AIUsageOption.disabledTools(settings.module(.aiUsage)?.options ?? [:]) == [.codex])
        row?.write(&settings, "true")
        let remaining = AIUsageOption.disabledTools(settings.module(.aiUsage)?.options ?? [:])
        #expect(remaining.isEmpty)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AIUsageSettingsSnapshotTests {
    @Test(arguments: [true, false])
    func settingsRows(dark: Bool) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlassWorkRows-\(UUID().uuidString)")
        let store = SettingsStore(file: SettingsFile(url: folder.appending(path: "settings.json")))
        store.update { $0.update(.aiUsage) { $0.options[AIUsageOption.enabledKey(.geminiCLI)] = "false" } }
        let view = Form {
            ModuleOptionRows(module: .aiUsage, store: store, showsAdvanced: true)
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 560)
        snapshotPanel(view, name: "ai-usage-settings", dark: dark)
    }

    @Test(arguments: [true, false])
    func emptyWithScanButton(dark: Bool) {
        let reading = AIUsageReading(tools: [], readAt: now)
        snapshotPanel(AIUsagePanel(reading: reading, refreshMinutes: 5, now: now), name: "ai-usage-scan", dark: dark)
    }

    @Test(arguments: [true, false])
    func updatingFooter(dark: Bool) {
        snapshotPanel(
            AIUsagePanel(reading: sample, refreshMinutes: 5, now: now, isUpdating: true),
            name: "ai-usage-updating",
            dark: dark
        )
    }
}
