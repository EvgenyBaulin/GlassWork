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
    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private var currentApp: String?
    @ObservationIgnored private var currentSince = Date()

    private static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
    private static let historyLimit = 30

    public init(store: SnapshotStore = SnapshotStore(), runner: ProcessRunning = ProcessRunner()) {
        self.store = store
        self.runner = runner
        screenTime = store.read(ScreenTimeLog.self, for: ScreenTimeLog.key) ?? ScreenTimeLog()
    }

    /// Credits the time to the app that was in front and starts the next one's clock.
    public func appBecameActive(_ name: String?, at date: Date = Date()) {
        if let currentApp {
            screenTime.record(app: currentApp, seconds: date.timeIntervalSince(currentSince), at: date)
            try? store.write(screenTime, for: ScreenTimeLog.key)
        }
        currentApp = name
        currentSince = date
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

    public func refreshGitHub() async {
        guard let tool = Self.ghPaths.first(where: FileManager.default.isExecutableFile) else {
            githubAvailable = false
            return
        }
        let fields = "title,repository,number,url,updatedAt"
        let review = ["search", "prs", "--review-requested=@me", "--state=open", "--json", fields]
        guard let output = try? await runner.run(tool, arguments: review, timeout: 20), output.status == 0 else {
            githubAvailable = false
            return
        }
        githubAvailable = true
        reviews = GitHubParser.pullRequests(Data(output.stdout.utf8))
        let query = "query{viewer{contributionsCollection{contributionCalendar{weeks{contributionDays"
            + "{date contributionCount}}}}}}"
        let graph = try? await runner.run(tool, arguments: ["api", "graphql", "-f", "query=\(query)"], timeout: 20)
        contributions = GitHubParser.contributions(Data((graph?.stdout ?? "").utf8))
    }
}
