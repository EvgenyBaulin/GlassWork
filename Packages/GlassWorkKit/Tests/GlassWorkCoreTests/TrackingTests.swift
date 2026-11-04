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
        let json = #"[{"title":"Fix","repository":{"nameWithOwner":"me/app"},"number":7,"url":"https://x/7","updatedAt":"2026-11-03T10:00:00Z"}]"#
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
        let json = #"{"data":{"viewer":{"contributionsCollection":{"contributionCalendar":{"weeks":[{"contributionDays":[{"date":"2026-11-01","contributionCount":0},{"date":"2026-11-02","contributionCount":3},{"date":"2026-11-03","contributionCount":1}]}]}}}}}"#
        let days = GitHubParser.contributions(Data(json.utf8))
        #expect(days.count == 3)
        #expect(GitHubParser.currentStreak(days) == 2)
    }
}
