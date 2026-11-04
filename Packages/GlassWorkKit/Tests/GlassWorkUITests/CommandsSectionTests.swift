import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Runs nothing: answers at once with the status asked for.
private struct FixedRunner: ProcessRunning {
    let status: Int32

    func run(_: String, arguments _: [String], timeout _: TimeInterval) async throws -> ProcessOutput {
        ProcessOutput(status: status, stdout: "", stderr: "")
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct CommandsSectionSnapshotTests {
    private func store(_ commands: [UserCommand]) -> SettingsStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlassWorkRun-\(UUID().uuidString)")
        let store = SettingsStore(file: SettingsFile(url: folder.appending(path: "settings.json")))
        store.update { $0.widgets.commands = commands }
        return store
    }

    private func activity() -> ActivityStore {
        ActivityStore(
            store: SnapshotStore(directory: sampleFolder()),
            runner: FixedRunner(status: 0),
            locateGH: { nil }
        )
    }

    private var commands: [UserCommand] {
        var deploy = UserCommand(name: "Deploy", command: "./deploy.sh")
        deploy.directory = "~/Developer/pocket-api"
        deploy.asksFirst = true
        return [UserCommand(name: "Run tests", command: "swift test"), deploy]
    }

    private func snapshot(selected: UUID?, list: [UserCommand], height: CGFloat, name: String, dark: Bool) {
        let view = Form {
            CommandsSection(store: store(list), activity: activity(), selected: selected)
        }
        .formStyle(.grouped)
        .frame(width: 620, height: height)
        snapshotPanel(view, name: name, dark: dark)
    }

    @Test(arguments: [true, false])
    func list(dark: Bool) {
        snapshot(selected: nil, list: commands, height: 220, name: "list", dark: dark)
    }

    @Test(arguments: [true, false])
    func editing(dark: Bool) {
        let list = commands
        snapshot(selected: list[1].id, list: list, height: 460, name: "editing", dark: dark)
    }

    @Test(arguments: [true, false])
    func actionsWidget(dark: Bool) {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var snapshot = WidgetSnapshot(date: date)
        snapshot.runs = [
            WorkflowRun(
                id: 1,
                name: "Build",
                branch: "main",
                state: .running,
                createdAt: date,
                repository: "me/glasswork"
            ),
            WorkflowRun(id: 2, name: "Tests", branch: "fix/ui", state: .failed, createdAt: date, repository: "me/api"),
        ]
        let view = ActionsWidget(size: .medium, snapshot: snapshot)
            .padding(16)
            .frame(width: WidgetSize.medium.width, height: WidgetSize.medium.height)
        snapshotPanel(view, name: "actions", dark: dark)
    }
}
