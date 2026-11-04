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
    public private(set) var github: WidgetGitHub?
    /// False when `gh` is missing or not signed in.
    public private(set) var githubAvailable = true

    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private var currentApp: String?
    @ObservationIgnored private var currentSince = Date()
    @ObservationIgnored private var pausedSince: Date?

    private static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    private static let historyLimit = 30

    public init(store: SnapshotStore = SnapshotStore(), runner: ProcessRunning = ProcessRunner()) {
        self.store = store
        self.runner = runner
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

    public func run(_ command: UserCommand) async {
        running.insert(command.id)
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

    /// `includesDigest` adds the query behind the GitHub widget, which costs one more call.
    public func refreshGitHub(includesDigest: Bool = false, at date: Date = Date()) async {
        guard let tool = Self.ghPaths.first(where: FileManager.default.isExecutableFile) else {
            githubAvailable = false
            github = WidgetGitHub(access: .notInstalled)
            return
        }
        let fields = "title,repository,number,url,updatedAt"
        let review = ["search", "prs", "--review-requested=@me", "--state=open", "--json", fields]
        guard let output = try? await runner.run(tool, arguments: review, timeout: 20), output.status == 0 else {
            githubAvailable = false
            github = WidgetGitHub(access: .notSignedIn)
            return
        }
        githubAvailable = true
        reviews = GitHubParser.pullRequests(Data(output.stdout.utf8))
        let query = "query{viewer{contributionsCollection{contributionCalendar{weeks{contributionDays"
            + "{date contributionCount}}}}}}"
        let graph = try? await runner.run(tool, arguments: ["api", "graphql", "-f", "query=\(query)"], timeout: 20)
        contributions = GitHubParser.contributions(Data((graph?.stdout ?? "").utf8))
        if includesDigest {
            await refreshDigest(tool: tool, at: date)
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
}
