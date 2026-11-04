import Foundation
@testable import GlassWorkCore
import Testing

/// `gh` is never really run here: a fake answers from a table and remembers what it was asked.
@MainActor
struct GitHubRunsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func runJSON(id: Int, title: String, date: String, status: String = "completed") -> String {
        """
        [{"databaseId": \(id), "displayTitle": "\(title)", "headBranch": "main", "status": "\(status)",
          "conclusion": "success", "createdAt": "\(date)"}]
        """
    }

    private nonisolated static func answer(
        _ arguments: [String],
        repos: String,
        runs: [String: String]
    ) -> ProcessOutput {
        if arguments.first == "search" {
            return ProcessOutput(status: 0, stdout: "[]", stderr: "")
        }
        if arguments.starts(with: ["api", "graphql"]) {
            return ProcessOutput(status: 0, stdout: "{}", stderr: "")
        }
        if arguments.first == "api" {
            return ProcessOutput(status: 0, stdout: repos, stderr: "")
        }
        if let repo = arguments.firstIndex(of: "--repo").map({ arguments[$0 + 1] }), let json = runs[repo] {
            return ProcessOutput(status: 0, stdout: json, stderr: "")
        }
        return ProcessOutput(status: 1, stdout: "", stderr: "no")
    }

    private func store(_ runner: FakeRunner, tool: String? = "/fake/gh") -> ActivityStore {
        ActivityStore(store: SnapshotStore(directory: temporaryFolder()), runner: runner, locateGH: { tool })
    }

    private func runner(repos: String = "me/one\nme/two\n", runs: [String: String]) -> FakeRunner {
        FakeRunner { _, arguments in Self.answer(arguments, repos: repos, runs: runs) }
    }

    private func runCalls(_ runner: FakeRunner) -> [[String]] {
        runner.calls.filter { $0.dropFirst().first == "run" }
    }

    @Test func runsAreFetchedForEachRepositoryNewestFirst() async {
        let runner = runner(runs: [
            "me/one": runJSON(id: 1, title: "Older", date: "2026-11-01T10:00:00Z"),
            "me/two": runJSON(id: 2, title: "Newer", date: "2026-11-02T10:00:00Z"),
        ])
        let store = store(runner)

        await store.refreshGitHub(includesRuns: true, at: start)

        #expect(store.runs.map(\.name) == ["Newer", "Older"])
        #expect(store.runs.first?.repository == "me/two")
        #expect(store.runs.first?.repositoryName == "two")
    }

    @Test func theRepositoryIsPassedExplicitly() async throws {
        let runner = runner(repos: "me/one\n", runs: ["me/one": "[]"])

        await store(runner).refreshGitHub(includesRuns: true, at: start)

        let call = try #require(runCalls(runner).first)
        #expect(Array(call.prefix(5)) == ["/fake/gh", "run", "list", "--repo", "me/one"])
    }

    @Test func runsAreNotFetchedUnlessAsked() async {
        let runner = runner(runs: [:])

        await store(runner).refreshGitHub(at: start)

        #expect(runCalls(runner).isEmpty)
    }

    @Test func aRefreshSoonAfterSkipsTheRuns() async {
        let runner = runner(repos: "me/one\n", runs: ["me/one": "[]"])
        let store = store(runner)

        await store.refreshGitHub(includesRuns: true, at: start)
        await store.refreshGitHub(includesRuns: true, at: start.addingTimeInterval(60))

        #expect(runCalls(runner).count == 1)
    }

    @Test func aRefreshLaterFetchesThemAgain() async {
        let runner = runner(repos: "me/one\n", runs: ["me/one": "[]"])
        let store = store(runner)

        await store.refreshGitHub(includesRuns: true, at: start)
        await store.refreshGitHub(includesRuns: true, at: start.addingTimeInterval(301))

        #expect(runCalls(runner).count == 2)
    }

    @Test func aRunUnderWayIsCheckedMoreOften() async {
        let json = runJSON(id: 1, title: "Build", date: "2026-11-01T10:00:00Z", status: "in_progress")
        let runner = runner(repos: "me/one\n", runs: ["me/one": json])
        let store = store(runner)

        await store.refreshGitHub(includesRuns: true, at: start)
        await store.refreshGitHub(includesRuns: true, at: start.addingTimeInterval(61))

        #expect(runCalls(runner).count == 2)
    }

    @Test func oneRepositoryFailingDoesNotCostTheOthers() async {
        let runner = runner(runs: ["me/two": runJSON(id: 2, title: "Fine", date: "2026-11-02T10:00:00Z")])
        let store = store(runner)

        await store.refreshGitHub(includesRuns: true, at: start)

        #expect(store.runs.map(\.name) == ["Fine"])
    }

    @Test func aFailedRepositoryListKeepsTheRunsAndIsReported() async {
        let failing = FakeRunner { _, arguments in
            if arguments.first == "search" {
                return ProcessOutput(status: 0, stdout: "[]", stderr: "")
            }
            return ProcessOutput(
                status: arguments.first == "api" && arguments[1] != "graphql" ? 4 : 0,
                stdout: "{}",
                stderr: ""
            )
        }
        let store = store(failing)
        var reported: [Int32] = []
        store.onGitHubFailed = { reported.append($0) }

        await store.refreshGitHub(includesRuns: true, at: start)

        #expect(reported == [4])
        #expect(store.runs.isEmpty)
        #expect(store.githubAvailable)
    }

    @Test func withoutGhNothingRuns() async {
        let runner = runner(runs: [:])
        let store = store(runner, tool: nil)

        await store.refreshGitHub(includesRuns: true, at: start)

        #expect(runner.calls.isEmpty)
        #expect(!store.githubAvailable)
    }

    @Test func repositoriesAreReadOnePerLine() {
        #expect(GitHubParser.repositories("me/one\n  me/two \n\nnoise\n") == ["me/one", "me/two"])
    }

    @Test func runsSavedBeforeTheRepositoryExistedStillDecode() throws {
        let json = #"{"id": 1, "name": "CI", "branch": "main", "state": "passed", "createdAt": 0}"#
        let run = try JSONDecoder().decode(WorkflowRun.self, from: Data(json.utf8))
        #expect(run.repository == nil)
        #expect(run.repositoryName == nil)
    }
}

@MainActor
struct CommandRunTests {
    private func store(_ runner: FakeRunner) -> ActivityStore {
        ActivityStore(store: SnapshotStore(directory: temporaryFolder()), runner: runner, locateGH: { nil })
    }

    @Test func aCommandRunsThroughTheShellAndKeepsItsResult() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 3, stdout: "out", stderr: "") }
        let store = store(runner)
        let command = UserCommand(name: "Build", command: "make build")

        await store.run(command)

        #expect(runner.calls == [["/bin/zsh", "-lc", "make build"]])
        #expect(store.commandResults[command.id]?.status == 3)
        #expect(store.running.isEmpty)
    }

    @Test func aSecondRunWhileRunningDoesNothing() async {
        let gate = AsyncStream<Void>.makeStream()
        let runner = SlowRunner(gate: gate.stream)
        let store = ActivityStore(
            store: SnapshotStore(directory: temporaryFolder()),
            runner: runner,
            locateGH: { nil }
        )
        let command = UserCommand(name: "Build", command: "make build")

        let first = Task { await store.run(command) }
        while store.running.isEmpty {
            await Task.yield()
        }
        await store.run(command)
        gate.continuation.finish()
        await first.value

        #expect(await runner.count == 1)
    }
}

/// Holds a command open until the test lets it finish.
private actor SlowRunner: ProcessRunning {
    private let gate: AsyncStream<Void>
    private(set) var count = 0

    init(gate: AsyncStream<Void>) {
        self.gate = gate
    }

    func run(_: String, arguments _: [String], timeout _: TimeInterval) async throws -> ProcessOutput {
        count += 1
        for await _ in gate {}
        return ProcessOutput(status: 0, stdout: "", stderr: "")
    }
}
