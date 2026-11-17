import Foundation
@testable import GlassWorkCore
import Testing

struct GitHubDetailParsingTests {
    private let runs = #"""
    [{"databaseId": 11, "displayTitle": "Build", "headBranch": "main", "status": "completed",
      "conclusion": "success", "createdAt": "2026-11-16T10:00:00Z", "startedAt": "2026-11-16T10:00:05Z",
      "updatedAt": "2026-11-16T10:02:20Z"},
     {"databaseId": 12, "displayTitle": "Deploy", "headBranch": "main", "status": "in_progress",
      "conclusion": "", "createdAt": "2026-11-16T11:00:00Z", "startedAt": "2026-11-16T11:00:02Z",
      "updatedAt": "2026-11-16T11:00:30Z"},
     {"databaseId": 13, "displayTitle": "Old", "headBranch": "x", "status": "completed",
      "conclusion": "failure", "createdAt": "2026-11-15T10:00:00Z"}]
    """#

    @Test func runsCarryStartAndEnd() {
        let list = GitHubParser.workflowRuns(Data(runs.utf8), repository: "me/app")
        #expect(list[0].duration == 135)
        #expect(list[0].completedAt == list[0].updatedAt)
        #expect(list[1].duration == nil)
        #expect(list[1].completedAt == nil)
        #expect(list[2].startedAt == nil)
        #expect(list[2].duration == nil)
    }

    @Test func reviewsCarryTheirCreationDate() {
        let json = #"""
        [{"title": "Fix", "repository": {"nameWithOwner": "me/app"}, "number": 7, "url": "https://x/7",
          "updatedAt": "2026-11-03T10:00:00Z", "createdAt": "2026-11-01T08:00:00Z"},
         {"title": "Old", "repository": {"nameWithOwner": "me/app"}, "number": 6, "url": "https://x/6",
          "updatedAt": "2026-11-03T10:00:00Z"}]
        """#
        let list = GitHubParser.pullRequests(Data(json.utf8))
        #expect(list[0].createdAt != nil)
        #expect(list[1].createdAt == nil)
    }

    @Test func parsesTheContributionTotalsAndTopRepositories() throws {
        let json = #"""
        {"data": {"viewer": {"contributionsCollection": {
          "totalCommitContributions": 120, "totalPullRequestContributions": 14, "totalIssueContributions": 3,
          "commitContributionsByRepository": [
            {"repository": {"nameWithOwner": "me/api"}, "contributions": {"totalCount": 30}},
            {"repository": {"nameWithOwner": "me/app"}, "contributions": {"totalCount": 80}}],
          "contributionCalendar": {"weeks": [{"contributionDays": [
            {"date": "2026-11-02", "contributionCount": 3}]}]}}}}}
        """#
        let data = Data(json.utf8)
        let summary = try #require(GitHubParser.contributionSummary(data))
        #expect(summary.commits == 120)
        #expect(summary.pullRequests == 14)
        #expect(summary.issues == 3)
        #expect(summary.repositories.map(\.name) == ["me/app", "me/api"])
        #expect(GitHubParser.contributions(data).count == 1)
    }

    @Test func anAnswerWithoutTotalsHasNoSummary() {
        #expect(GitHubParser.contributionSummary(Data("{}".utf8)) == nil)
        #expect(GitHubParser.contributionsQuery.contains("commitContributionsByRepository(maxRepositories:3)"))
        #expect(!GitHubParser.contributionsQuery.contains("\n"))
    }
}

struct GitHubSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private func run(_ id: Int, _ state: WorkflowState, hoursAgo: Double, minutes: Double? = nil) -> WorkflowRun {
        let created = now.addingTimeInterval(-hoursAgo * 3600)
        return WorkflowRun(
            id: id,
            name: "CI",
            branch: "main",
            state: state,
            createdAt: created,
            startedAt: created,
            updatedAt: minutes.map { created.addingTimeInterval($0 * 60) }
        )
    }

    @Test func totalsAndWeekRate() {
        // 1_800_000_000 is 08:00 UTC, so anything within eight hours is today.
        let runs = [
            run(1, .running, hoursAgo: 0.1),
            run(2, .passed, hoursAgo: 1, minutes: 4),
            run(3, .failed, hoursAgo: 2, minutes: 2),
            run(4, .passed, hoursAgo: 72, minutes: 6),
            run(5, .other, hoursAgo: 80, minutes: 1),
            run(6, .failed, hoursAgo: 24 * 9, minutes: 1),
        ]
        let summary = WorkflowSummary(runs: runs, now: now, calendar: calendar)
        #expect(summary.running == 1)
        #expect(summary.today == 3)
        #expect(summary.todayFailed == 1)
        #expect(summary.weekFinished == 3)
        #expect(abs((summary.weekSuccessRate ?? 0) - 2.0 / 3.0) < 0.001)
        #expect(summary.averageDuration == TimeInterval(195))
    }

    @Test func noFinishedRunsMeansNoRate() {
        let summary = WorkflowSummary(runs: [run(1, .running, hoursAgo: 1)], now: now, calendar: calendar)
        #expect(summary.weekSuccessRate == nil)
        #expect(summary.averageDuration == nil)
    }

    @Test func reviewAgesFallInThreeBuckets() {
        func pull(_ number: Int, daysAgo: Double?) -> PullRequest {
            PullRequest(
                title: "T",
                repository: "me/app",
                number: number,
                url: "https://x/\(number)",
                updatedAt: now,
                createdAt: daysAgo.map { now.addingTimeInterval(-$0 * 86400) }
            )
        }
        let wait = ReviewWait(
            reviews: [
                pull(1, daysAgo: 0.2), pull(2, daysAgo: 1), pull(3, daysAgo: 3), pull(4, daysAgo: 5),
                pull(5, daysAgo: nil),
            ],
            now: now
        )
        #expect(wait.fresh == 1)
        #expect(wait.middle == 2)
        #expect(wait.stale == 1)
        #expect(wait.total == 4)
        #expect(wait.oldest == TimeInterval(5 * 86400))
        #expect(ReviewWait(reviews: [], now: now).oldest == nil)
    }
}

/// Hands out the run list for each read in turn.
private final class Answers: @unchecked Sendable {
    // Why unchecked: the lock guards `queue`, the only mutable state.
    private let lock = NSLock()
    private var queue: [String]

    init(_ queue: [String]) {
        self.queue = queue
    }

    func next() -> String {
        lock.withLock { queue.isEmpty ? "[]" : queue.removeFirst() }
    }
}

@MainActor
struct GitHubHistoryTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func list(_ ids: [Int: Double]) -> String {
        let rows = ids.sorted { $0.key < $1.key }.map { id, daysAgo in
            let date = ISO8601DateFormatter().string(from: start.addingTimeInterval(-daysAgo * 86400))
            return """
            {"databaseId": \(id), "displayTitle": "Run \(id)", "headBranch": "main", "status": "completed",
             "conclusion": "success", "createdAt": "\(date)", "startedAt": "\(date)", "updatedAt": "\(date)"}
            """
        }
        return "[" + rows.joined(separator: ",") + "]"
    }

    private func store(_ answers: Answers) -> ActivityStore {
        let runner = FakeRunner { _, arguments in
            if arguments.first == "search" {
                return ProcessOutput(status: 0, stdout: "[]", stderr: "")
            }
            if arguments.starts(with: ["api", "graphql"]) {
                return ProcessOutput(status: 0, stdout: "{}", stderr: "")
            }
            if arguments.first == "api" {
                return ProcessOutput(status: 0, stdout: "me/one\n", stderr: "")
            }
            return ProcessOutput(status: 0, stdout: answers.next(), stderr: "")
        }
        return ActivityStore(
            store: SnapshotStore(directory: temporaryFolder()),
            runner: runner,
            locateGH: { "/fake/gh" }
        )
    }

    @Test func earlierRunsStayForAWeekAndNoLonger() async {
        let store = store(Answers([list([1: 6.5, 2: 1]), list([3: 0])]))
        await store.refreshGitHub(includesRuns: true, at: start)
        #expect(store.runs.map(\.id) == [2, 1])
        // A day later run 1 is past the week; run 2 stays, run 3 is new.
        await store.refreshGitHub(includesRuns: true, at: start.addingTimeInterval(86400 + 301))
        #expect(store.runs.map(\.id) == [3, 2])
    }

    @Test func accessIsRecordedForTheWidgets() async {
        let missing = ActivityStore(
            store: SnapshotStore(directory: temporaryFolder()),
            runner: FakeRunner { _, _ in ProcessOutput(status: 0, stdout: "", stderr: "") },
            locateGH: { nil }
        )
        await missing.refreshGitHub(at: start)
        #expect(missing.githubAccess == .notInstalled)
        let failing = ActivityStore(
            store: SnapshotStore(directory: temporaryFolder()),
            runner: FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") },
            locateGH: { "/fake/gh" }
        )
        await failing.refreshGitHub(at: start)
        #expect(failing.githubAccess == .notSignedIn)
        let ready = store(Answers([]))
        await ready.refreshGitHub(at: start)
        #expect(ready.githubAccess == .ready)
    }
}
