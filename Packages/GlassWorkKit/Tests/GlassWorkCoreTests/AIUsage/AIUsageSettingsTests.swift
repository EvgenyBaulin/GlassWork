import Foundation
@testable import GlassWorkCore
import Observation
import Synchronization
import Testing

struct AIUsageSettingsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var reading: AIUsageReading {
        AIUsageReading(
            tools: [
                AIToolUsage(tool: .claudeCode, windows: [AIWindow(kind: .fiveHour, used: 0.4, resetsAt: nil)]),
                AIToolUsage(tool: .codex, windows: [AIWindow(kind: .fiveHour, used: 0.7, resetsAt: nil)]),
            ],
            readAt: now
        ).warning(at: 0.8)
    }

    @Test func everyToolIsOnByDefault() {
        #expect(AIUsageOption.disabledTools([:]).isEmpty)
        #expect(AIUsageOption.chosenTool([:]) == nil)
    }

    @Test func aToolSwitchedOffIsListed() {
        let options = [AIUsageOption.enabledKey(.codex): "false", AIUsageOption.enabledKey(.droid): "true"]

        #expect(AIUsageOption.disabledTools(options) == [.codex])
    }

    @Test func theMenuBarToolIsReadFromItsRawValue() {
        #expect(AIUsageOption.chosenTool([AIUsageOption.menuBarTool: AITool.codex.rawValue]) == .codex)
        #expect(AIUsageOption.chosenTool([AIUsageOption.menuBarTool: AIUsageOption.highestTool]) == nil)
        #expect(AIUsageOption.chosenTool([AIUsageOption.menuBarTool: "unknown"]) == nil)
    }

    @Test func excludingDropsToolsAndKeepsThemOffTheMissingList() {
        let filtered = reading.excluding([.codex])

        #expect(filtered.tools.map(\.tool) == [.claudeCode])
        #expect(!filtered.missing.contains(.codex))
        #expect(filtered.warnLevel == 0.8)
        #expect(reading.excluding([]).disabled == nil)
    }

    @Test func aChosenToolIsTheOnlyOneInTheReading() {
        let one = reading.only(.claudeCode)

        #expect(one.tools.map(\.tool) == [.claudeCode])
        #expect(one.peak(at: now)?.window.used == 0.4)
        #expect(one.warnLevel == 0.8)
    }

    @Test func aDisabledToolIsNotRead() async throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "GlassWorkAI-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for folder in [".codex/sessions", ".claude/projects"] {
            try FileManager.default.createDirectory(
                at: home.appending(path: folder),
                withIntermediateDirectories: true
            )
        }
        let collector = AIUsageCollector(
            runner: FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") },
            home: home.path,
            locate: { _ in nil }
        )

        let all = await collector.read(at: now)
        let some = await collector.read(at: now, skipping: [.codex])

        #expect(all.tools.map(\.tool).contains(.codex))
        #expect(some.tools.map(\.tool) == [.claudeCode])
        #expect(!some.missing.contains(.codex))
    }
}

@MainActor
struct AIUsageStoreStateTests {
    private func store() -> DeveloperStore {
        DeveloperStore(
            runner: FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") },
            home: FileManager.default.temporaryDirectory.appending(path: "GlassWorkAI-\(UUID().uuidString)").path,
            locateGit: { nil }
        )
    }

    @Test func theStoreIsUpdatingWhileAReadIsInFlight() async {
        let store = store()
        #expect(!store.isUpdating(.aiUsage))

        let changes = Mutex(0)
        withObservationTracking { _ = store.isUpdating(.aiUsage) } onChange: { changes.withLock { $0 += 1 } }
        store.refresh(.aiUsage)

        #expect(store.isUpdating(.aiUsage))
        #expect(changes.withLock { $0 } == 1)
        for _ in 0 ..< 200 where store.isUpdating(.aiUsage) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!store.isUpdating(.aiUsage))
    }

    @Test func switchingAToolOffRemovesItAtOnce() {
        let store = store()
        let saved = AIUsageReading(
            tools: [AIToolUsage(tool: .claudeCode), AIToolUsage(tool: .codex)],
            readAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        store.restore(aiUsage: saved)

        var settings = AppSettings()
        settings.update(.aiUsage) { $0.options[AIUsageOption.enabledKey(.codex)] = "false" }
        store.options = DeveloperOptions(settings: settings)

        #expect(store.aiUsage?.tools.map(\.tool) == [.claudeCode])
    }
}
