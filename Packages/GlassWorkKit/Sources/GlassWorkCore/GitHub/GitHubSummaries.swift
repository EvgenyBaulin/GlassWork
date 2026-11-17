import Foundation

// swiftlint:disable nesting

/// What the Actions widget says about the runs: what is going now, today, and over the last week.
public struct WorkflowSummary: Equatable, Sendable {
    public var running = 0
    /// Runs started today.
    public var today = 0
    public var todayFailed = 0
    /// Share of finished runs in the last seven days that passed; nil when none has finished.
    public var weekSuccessRate: Double?
    public var weekFinished = 0
    public var averageDuration: TimeInterval?

    public init(runs: [WorkflowRun], now: Date, calendar: Calendar = .current) {
        running = runs.count { $0.state == .running }
        let todays = runs.filter { calendar.isDate($0.createdAt, inSameDayAs: now) }
        today = todays.count
        todayFailed = todays.count { $0.state == .failed }
        let week = runs.filter { $0.createdAt >= now.addingTimeInterval(-7 * 86400) && $0.createdAt <= now }
        // Cancelled and skipped runs say nothing about whether the build is healthy.
        let passed = week.count { $0.state == .passed }
        let failed = week.count { $0.state == .failed }
        weekFinished = passed + failed
        weekSuccessRate = weekFinished == 0 ? nil : Double(passed) / Double(weekFinished)
        let durations = week.compactMap(\.duration)
        averageDuration = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
    }
}

/// How long the review requests have been waiting, in the three buckets the Reviews widget draws.
public struct ReviewWait: Equatable, Sendable {
    public var oldest: TimeInterval?
    /// Under a day.
    public var fresh = 0
    /// A day up to three.
    public var middle = 0
    /// More than three days.
    public var stale = 0

    public init(reviews: [PullRequest], now: Date) {
        // Requests saved before the age was kept have no date and are left out rather than guessed.
        let ages = reviews.compactMap { $0.createdAt.map { max(now.timeIntervalSince($0), 0) } }
        oldest = ages.max()
        for age in ages {
            switch age {
            case ..<86400: fresh += 1
            case ...(3 * 86400): middle += 1
            default: stale += 1
            }
        }
    }

    public var total: Int {
        fresh + middle + stale
    }
}

/// Totals for the contribution period and the repositories with the most commits.
public struct ContributionSummary: Codable, Sendable, Equatable {
    public struct Repository: Codable, Sendable, Equatable {
        public var name: String
        public var commits: Int

        public init(name: String, commits: Int) {
            self.name = name
            self.commits = commits
        }
    }

    public var commits: Int
    public var pullRequests: Int
    public var issues: Int
    public var repositories: [Repository]

    public init(commits: Int, pullRequests: Int, issues: Int, repositories: [Repository] = []) {
        self.commits = commits
        self.pullRequests = pullRequests
        self.issues = issues
        self.repositories = repositories
    }
}

public extension GitHubParser {
    /// The totals from the same `gh api graphql` answer as the calendar. Nil when the answer has none.
    static func contributionSummary(_ json: Data) -> ContributionSummary? {
        struct Root: Decodable {
            struct Repository: Decodable {
                struct Name: Decodable { let nameWithOwner: String }
                struct Count: Decodable { let totalCount: Int }
                let repository: Name
                let contributions: Count
            }

            struct Collection: Decodable {
                let totalCommitContributions: Int
                let totalPullRequestContributions: Int
                let totalIssueContributions: Int
                let commitContributionsByRepository: [Repository]?
            }

            struct Viewer: Decodable { let contributionsCollection: Collection }
            struct Payload: Decodable { let viewer: Viewer }
            let data: Payload
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: json) else { return nil }
        let collection = root.data.viewer.contributionsCollection
        let repositories = (collection.commitContributionsByRepository ?? [])
            .map { ContributionSummary.Repository(
                name: $0.repository.nameWithOwner,
                commits: $0.contributions.totalCount
            ) }
            .sorted { $0.commits > $1.commits }
        return ContributionSummary(
            commits: collection.totalCommitContributions,
            pullRequests: collection.totalPullRequestContributions,
            issues: collection.totalIssueContributions,
            repositories: repositories
        )
    }
}

// swiftlint:enable nesting

@MainActor
extension WidgetSnapshot {
    /// What the Reviews, Actions and Contributions widgets list, and whether `gh` lets them.
    mutating func copyLists(from activity: ActivityStore) {
        reviews = activity.reviews
        runs = activity.runs
        contributions = activity.contributions
        contributionSummary = activity.contributionSummary
        githubAccess = activity.githubAccess
    }
}
