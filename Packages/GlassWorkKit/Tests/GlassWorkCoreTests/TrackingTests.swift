import Foundation
@testable import GlassWorkCore
import Testing

struct ScreenTimeTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func addsUpTimePerApp() throws {
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 60, at: date)
        log.record(app: "Xcode", seconds: 30, at: date)
        log.record(app: "Safari", seconds: 10, at: date)

        let day = try #require(log.days.last)
        #expect(day.total == 100)
        #expect(log.topApps(in: day, limit: 1).first?.app == "Xcode")
    }

    @Test func skipsExcludedApps() {
        var log = ScreenTimeLog()
        log.excluded = ["Secret"]
        log.record(app: "Secret", seconds: 60, at: date)
        #expect(log.days.isEmpty)
    }

    @Test func keepsThirtyDays() {
        var log = ScreenTimeLog()
        for day in 0 ..< 40 {
            log.record(app: "Xcode", seconds: 1, at: date.addingTimeInterval(Double(day) * 86400))
        }
        #expect(log.days.count == ScreenTimeLog.keepDays)
    }
}

struct CommandTests {
    struct FakeRunner: ProcessRunning {
        func run(_: String, arguments: [String], timeout _: TimeInterval) async throws -> ProcessOutput {
            ProcessOutput(status: 0, stdout: "one\ntwo\n\(arguments.last ?? "")", stderr: "")
        }
    }

    @Test func runsInItsDirectory() async {
        var command = UserCommand(name: "Tests", command: "make test")
        command.directory = "/tmp/it's here"

        let result = await CommandRunner.run(command, using: FakeRunner())

        #expect(result.status == 0)
        #expect(result.tail.contains(#"cd '/tmp/it'\''s here' && make test"#))
    }

    @Test func keepsTheLastLines() {
        #expect(CommandResult.tail(of: "1\n2\n3\n4\n5\n", lines: 2) == "4\n5")
    }

    @Test func comparesEndpointStatus() {
        let check = EndpointCheck(date: Date(), status: 503, milliseconds: 80)
        #expect(!check.isUp(expected: 200))
    }
}

struct GitHubParserTests {
    @Test func parsesPullRequests() {
        let json = #"""
        [{"title": "Fix", "repository": {"nameWithOwner": "me/app"}, "number": 7,
          "url": "https://x/7", "updatedAt": "2026-11-03T10:00:00Z"}]
        """#
        let list = GitHubParser.pullRequests(Data(json.utf8))
        #expect(list.first?.repository == "me/app")
        #expect(list.first?.number == 7)
    }

    @Test(arguments: [
        ("in_progress", nil as String?, WorkflowState.running),
        ("completed", "success", .passed),
        ("completed", "failure", .failed),
        ("completed", "cancelled", .other),
    ])
    func mapsRunStates(status: String, conclusion: String?, expected: WorkflowState) {
        #expect(GitHubParser.state(status: status, conclusion: conclusion) == expected)
    }

    @Test func parsesContributionsAndStreak() {
        let json = #"""
        {"data": {"viewer": {"contributionsCollection": {"contributionCalendar": {"weeks": [{"contributionDays": [
            {"date": "2026-11-01", "contributionCount": 0},
            {"date": "2026-11-02", "contributionCount": 3},
            {"date": "2026-11-03", "contributionCount": 1}
        ]}]}}}}}
        """#
        let days = GitHubParser.contributions(Data(json.utf8))
        #expect(days.count == 3)
        #expect(GitHubParser.currentStreak(days) == 2)
    }
}

struct PullRequestDigestTests {
    private let answer = """
    {"data":{"requested":{"nodes":[
      {"title":"Glass cards","number":142,"url":"https://github.com/o/r/pull/142",
       "updatedAt":"2026-11-02T10:00:00Z","additions":412,"deletions":88,"reviewDecision":"REVIEW_REQUIRED",
       "repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}},
      {}
    ]},"viewer":{"pullRequests":{"nodes":[
      {"title":"Feed","number":145,"url":"https://github.com/o/r/pull/145","updatedAt":"2026-11-02T11:00:00Z",
       "additions":1,"deletions":2,"reviewDecision":"APPROVED","repository":{"nameWithOwner":"o/r"},
       "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"FAILURE"},
         {"__typename":"CheckRun","status":"IN_PROGRESS","conclusion":null},
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SKIPPED"},
         {"__typename":"StatusContext","state":"SUCCESS"},
         {"__typename":"StatusContext","state":"PENDING"}
       ]}}}}]}}
    ]}}}}
    """

    @Test func readsBothLists() throws {
        let digest = try #require(GitHubParser.digest(Data(answer.utf8)))
        #expect(digest.requested.map(\.number) == [142])
        #expect(digest.requested[0].additions == 412)
        #expect(digest.requested[0].review == .none)
        #expect(digest.requested[0].checks == .none)
        #expect(digest.mine[0].review == .approved)
    }

    @Test func countsChecksOfBothKinds() throws {
        let pull = try #require(GitHubParser.digest(Data(answer.utf8))?.mine.first)
        #expect(pull.checksPassed == 2)
        #expect(pull.checksFailed == 1)
        #expect(pull.checksRunning == 2)
        #expect(pull.checksTotal == 5)
    }

    @Test func aFailureOutweighsARun() {
        let date = Date()
        let pull = PullRequestSummary(
            title: "", repository: "", number: 1, url: "", updatedAt: date, checksFailed: 1, checksRunning: 3
        )
        #expect(pull.checks == .failing)
    }

    @Test(arguments: ["", "not json", "{\"errors\":[{\"message\":\"nope\"}]}"])
    func anythingElseIsNil(text: String) {
        #expect(GitHubParser.digest(Data(text.utf8)) == nil)
    }

    @Test func theQueryStaysOnOneLine() {
        #expect(!GitHubParser.digestQuery.contains("\n"))
        #expect(GitHubParser.digestQuery.contains("review-requested:@me"))
    }
}

struct SystemOnlyWidgetTests {
    @Test func newWidgetsStayOutOfTheAppsOwnWindows() {
        #expect(WidgetKind.gallery.allSatisfy { !WidgetKind.systemOnlyKinds.contains($0) })
    }

    @Test func todayAskForTheBattery() {
        #expect(MonitorDemand(widgets: [.todayAtAGlance]).battery)
    }

    @Test func theGitHubWidgetRunsTheTool() {
        #expect(WidgetKind.githubKinds.contains(.github))
    }
}
