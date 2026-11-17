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
    public private(set) var contributionSummary: ContributionSummary?
    public private(set) var github: WidgetGitHub?
    /// Why the GitHub widgets have nothing to show, when they do not.
    public private(set) var githubAccess: WidgetGitHub.Access = .ready
    /// False when `gh` is missing or not signed in.
    public private(set) var githubAvailable = true

    @ObservationIgnored private let store: SnapshotStore
    /// Reports the exit status when `gh` fails, for the diagnostic log.
    @ObservationIgnored public var onGitHubFailed: ((Int32) -> Void)?

    /// Called after the data was deleted, so widgets can be written again at once.
    @ObservationIgnored public var onScreenTimeReset: (() -> Void)?

    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let locateGH: @Sendable () -> String?
    @ObservationIgnored private var lastRunsRead: Date?
    @ObservationIgnored private var currentApp: String?
    @ObservationIgnored private var currentSince = Date()
    @ObservationIgnored private var pausedSince: Date?

    private static let historyLimit = 30
    /// Every repository costs a call, and this runs from a widget refresh, so the list stays short.
    private static let repositoryLimit = 5
    /// Enough per repository to cover a week of runs for the success rate.
    private static let runsPerRepository = 20
    /// Runs are kept for a week, so the success rate has something to count, up to this many.
    private static let runLimit = 200
    private static let runHistory: TimeInterval = 7 * 86400
    private static let runFields = "databaseId,displayTitle,headBranch,status,conclusion,createdAt,startedAt,updatedAt"
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

    /// Counts what was in front up to now first, so the time before the change keeps the old rules.
    public func configureScreenTime(dayStartHour: Int, excluded: Set<String>, at date: Date = Date()) {
        let hour = min(max(dayStartHour, 0), 6)
        guard hour != screenTime.dayStartHour || excluded != screenTime.excluded else { return }
        creditCurrentApp(at: date)
        currentSince = date
        screenTime.dayStartHour = hour
        screenTime.excluded = excluded
        try? store.write(screenTime, for: ScreenTimeLog.key)
    }

    /// Deletes the days kept so far. The exclusions and the day start stay: they are settings, not data.
    public func resetScreenTime(at date: Date = Date()) {
        var empty = ScreenTimeLog()
        empty.dayStartHour = screenTime.dayStartHour
        empty.excluded = screenTime.excluded
        screenTime = empty
        currentSince = date
        // Away from the Mac now: the break counts from the reset, not from before it.
        if pausedSince != nil {
            pausedSince = date
        }
        try? store.write(screenTime, for: ScreenTimeLog.key)
        onScreenTimeReset?()
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

    public func check(_ endpoints: [Endpoint], at date: Date = Date()) async {
        for endpoint in endpoints where endpoint.isDue(lastCheck: endpointChecks[endpoint.id]?.last?.date, at: date) {
            let result = await EndpointChecker.check(endpoint)
            endpointChecks[endpoint.id, default: []].append(result)
            endpointChecks[endpoint.id] = endpointChecks[endpoint.id]?.suffix(Self.historyLimit).map(\.self)
        }
    }

    /// - Parameters:
    ///   - includesDigest: Adds the query behind the GitHub widget, which costs one more call.
    ///   - includesRuns: Only the Actions widget needs runs, and they cost a call per repository.
    public func refreshGitHub(
        includesDigest: Bool = false,
        includesRuns: Bool = false,
        at date: Date = Date()
    ) async {
        guard let tool = locateGH() else {
            githubAvailable = false
            githubAccess = .notInstalled
            github = WidgetGitHub(access: .notInstalled)
            return
        }
        let fields = "title,repository,number,url,updatedAt,createdAt"
        let review = ["search", "prs", "--review-requested=@me", "--state=open", "--json", fields]
        let output = try? await runner.run(tool, arguments: review, timeout: 20)
        guard let output, output.status == 0 else {
            githubAvailable = false
            githubAccess = .notSignedIn
            github = WidgetGitHub(access: .notSignedIn)
            onGitHubFailed?(output?.status ?? -1)
            return
        }
        githubAvailable = true
        githubAccess = .ready
        reviews = GitHubParser.pullRequests(Data(output.stdout.utf8))
        let query = GitHubParser.contributionsQuery
        let graph = try? await runner.run(tool, arguments: ["api", "graphql", "-f", "query=\(query)"], timeout: 20)
        let graphData = Data((graph?.stdout ?? "").utf8)
        contributions = GitHubParser.contributions(graphData)
        contributionSummary = GitHubParser.contributionSummary(graphData)
        if includesDigest {
            await refreshDigest(tool: tool, at: date)
        }
        if includesRuns {
            await refreshRuns(tool, at: date)
        }
    }

    /// A failed call leaves the last good lists on the widget.
    private func refreshDigest(tool: String, at date: Date) async {
        let arguments = ["api", "graphql", "-f", "query=\(GitHubParser.digestQuery)"]
        let answer = try? await runner.run(tool, arguments: arguments, timeout: 20)
        if let digest = GitHubParser.digest(Data((answer?.stdout ?? "").utf8)) {
            github = WidgetGitHub(requested: digest.requested, mine: digest.mine, updatedAt: date)
        } else if github?.access != .ready {
            github = WidgetGitHub()
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
        // Runs read earlier stay for a week unless the new answer has them again, so the rate has a week to count.
        let known = Set(fresh.map(\.id))
        let cutoff = date.addingTimeInterval(-Self.runHistory)
        let kept = runs.filter { !known.contains($0.id) && $0.createdAt >= cutoff }
        runs = Array((fresh + kept).sorted { $0.createdAt > $1.createdAt }.prefix(Self.runLimit))
    }
}
