import Foundation
import Observation

/// Live data for the screen time, commands, endpoints and GitHub widgets.
@MainActor
@Observable
public final class ActivityStore {
    public private(set) var screenTime: ScreenTimeLog
    public private(set) var commandResults: [UUID: CommandResult] = [:]
    public private(set) var running: Set<UUID> = []
    public private(set) var endpointChecks: [UUID: [EndpointCheck]] = [:]
    public private(set) var reviews: [PullRequest] = []
    public private(set) var runs: [WorkflowRun] = []
    public private(set) var contributions: [ContributionDay] = []
    /// False when `gh` is missing or not signed in.
    public private(set) var githubAvailable = true

    @ObservationIgnored private let store: SnapshotStore
    /// Reports the exit status when `gh` fails, for the diagnostic log.
    @ObservationIgnored public var onGitHubFailed: ((Int32) -> Void)?

    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let locateGH: @Sendable () -> String?
    @ObservationIgnored private var lastRunsRead: Date?
    @ObservationIgnored private var currentApp: String?
    @ObservationIgnored private var currentSince = Date()
    @ObservationIgnored private var pausedSince: Date?

    private static let historyLimit = 30
    /// Every repository costs a call, and this runs from a widget refresh, so the list stays short.
    private static let repositoryLimit = 5
    private static let runsPerRepository = 5
    private static let runLimit = 12
    private static let runFields = "databaseId,displayTitle,headBranch,status,conclusion,createdAt"
    private static let idleRunsInterval: TimeInterval = 300
    /// A run under way is what someone is waiting for, so it is checked more often.
    private static let activeRunsInterval: TimeInterval = 60

    public init(
        store: SnapshotStore = SnapshotStore(),
        runner: ProcessRunning = ProcessRunner(),
        locateGH: @escaping @Sendable () -> String? = { ToolLocator.find("gh") }
    ) {
        self.store = store
        self.runner = runner
        self.locateGH = locateGH
        screenTime = store.read(ScreenTimeLog.self, for: ScreenTimeLog.key) ?? ScreenTimeLog()
    }

    /// Credits the time to the app that was in front and starts the next one's clock.
    public func appBecameActive(_ name: String?, category: AppCategory? = nil, at date: Date = Date()) {
        creditCurrentApp(at: date)
        if let name, let category {
            screenTime.categories[name] = category
        }
        currentApp = name
        currentSince = date
    }

    /// Counts the time so far without changing the app, so widgets see a long session as it runs.
    public func flushScreenTime(at date: Date = Date()) {
        creditCurrentApp(at: date)
        currentSince = date
    }

    /// The screen locked or went to sleep: the time from here on is not at the Mac.
    public func screenWentAway(at date: Date = Date()) {
        guard pausedSince == nil else { return }
        creditCurrentApp(at: date)
        pausedSince = date
    }

    public func screenCameBack(at date: Date = Date()) {
        guard let start = pausedSince else { return }
        pausedSince = nil
        currentSince = date
        screenTime.recordBreak(from: start, to: date)
        try? store.write(screenTime, for: ScreenTimeLog.key)
    }

    private func creditCurrentApp(at date: Date) {
        guard let currentApp, pausedSince == nil else { return }
        screenTime.record(app: currentApp, seconds: date.timeIntervalSince(currentSince), at: date)
        try? store.write(screenTime, for: ScreenTimeLog.key)
    }

    /// A second click while it runs does nothing: a command must not start twice by accident.
    public func run(_ command: UserCommand) async {
        guard running.insert(command.id).inserted else { return }
        commandResults[command.id] = await CommandRunner.run(command, using: runner)
        running.remove(command.id)
    }

    public func check(_ endpoints: [Endpoint]) async {
        for endpoint in endpoints {
            let result = await EndpointChecker.check(endpoint)
            endpointChecks[endpoint.id, default: []].append(result)
            endpointChecks[endpoint.id] = endpointChecks[endpoint.id]?.suffix(Self.historyLimit).map(\.self)
        }
    }

    /// - Parameter includesRuns: Only the Actions widget needs runs, and they cost a call per repository.
    public func refreshGitHub(includesRuns: Bool = false, at date: Date = Date()) async {
        guard let tool = locateGH() else {
            githubAvailable = false
            return
        }
        let fields = "title,repository,number,url,updatedAt"
        let review = ["search", "prs", "--review-requested=@me", "--state=open", "--json", fields]
        let output = try? await runner.run(tool, arguments: review, timeout: 20)
        guard let output, output.status == 0 else {
            githubAvailable = false
            onGitHubFailed?(output?.status ?? -1)
            return
        }
        githubAvailable = true
        reviews = GitHubParser.pullRequests(Data(output.stdout.utf8))
        let query = "query{viewer{contributionsCollection{contributionCalendar{weeks{contributionDays"
            + "{date contributionCount}}}}}}"
        let graph = try? await runner.run(tool, arguments: ["api", "graphql", "-f", "query=\(query)"], timeout: 20)
        contributions = GitHubParser.contributions(Data((graph?.stdout ?? "").utf8))
        if includesRuns {
            await refreshRuns(tool, at: date)
        }
    }

    /// The latest runs across the repositories pushed to most recently. `gh run list` works on one repository
    /// at a time and the app has no working folder, so `gh` is asked which ones those are: no local file is read.
    private func refreshRuns(_ tool: String, at date: Date) async {
        let isActive = runs.contains { $0.state == .running }
        let interval = isActive ? Self.activeRunsInterval : Self.idleRunsInterval
        if let lastRunsRead, date.timeIntervalSince(lastRunsRead) < interval {
            return
        }
        lastRunsRead = date
        let list = ["api", "user/repos?sort=pushed&per_page=\(Self.repositoryLimit)", "--jq", ".[].full_name"]
        let repositories = try? await runner.run(tool, arguments: list, timeout: 20)
        guard let repositories, repositories.status == 0 else {
            onGitHubFailed?(repositories?.status ?? -1)
            return
        }
        var fresh: [WorkflowRun] = []
        for repository in GitHubParser.repositories(repositories.stdout) {
            let arguments = [
                "run", "list", "--repo", repository,
                "--limit", String(Self.runsPerRepository), "--json", Self.runFields,
            ]
            // One repository without Actions, or one that fails, must not cost the others.
            if let output = try? await runner.run(tool, arguments: arguments, timeout: 20), output.status == 0 {
                fresh += GitHubParser.workflowRuns(Data(output.stdout.utf8), repository: repository)
            }
        }
        runs = Array(fresh.sorted { $0.createdAt > $1.createdAt }.prefix(Self.runLimit))
    }
}
