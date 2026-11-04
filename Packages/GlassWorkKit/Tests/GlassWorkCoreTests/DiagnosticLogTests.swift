import Foundation
@testable import GlassWorkCore
import Testing

/// Every test logs into a folder of its own, never into the user's Logs.
struct DiagnosticLogTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func url() -> URL {
        temporaryFolder().appending(path: "Logs/diagnostic.log")
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func lines(_ url: URL) throws -> [Substring] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
    }

    @Test func offIsTheDefault() {
        #expect(!AppSettings().keepsDiagnosticLog)
    }

    @Test func whileOffNothingTouchesTheDisk() async {
        let url = url()
        let log = DiagnosticLog(url: url)

        await log.record(.settingsProblem, at: start)

        #expect(!exists(url))
        #expect(!exists(url.deletingLastPathComponent()))
    }

    @Test func turningItOffWhenItWasNeverOnLeavesTheDiskAlone() async throws {
        let url = url()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("kept\n".utf8).write(to: url)

        await DiagnosticLog(url: url).setEnabled(false)

        #expect(exists(url))
    }

    @Test func writesOneLinePerEvent() async throws {
        let url = url()
        let log = DiagnosticLog(url: url)
        await log.setEnabled(true, at: start)

        await log.record(.settingsProblem, at: start)
        await log.record(.gitHubFailed(status: 4), at: start)

        let written = try lines(url)
        #expect(written.count == 2)
        #expect(written[0].hasSuffix("settings file could not be read or saved"))
        #expect(written[1].hasSuffix("gh failed with status 4"))
    }

    @Test func turningItOffDeletesTheFile() async {
        let url = url()
        let log = DiagnosticLog(url: url)
        await log.setEnabled(true, at: start)
        await log.record(.settingsProblem, at: start)
        #expect(exists(url))

        await log.setEnabled(false)
        await log.record(.settingsProblem, at: start)

        #expect(!exists(url))
    }

    @Test func dropsWhatIsPastItsWeek() async throws {
        let url = url()
        let log = DiagnosticLog(url: url)
        await log.setEnabled(true, at: start)
        await log.record(.settingsProblem, at: start)
        await log.record(.gitHubFailed(status: 1), at: start.addingTimeInterval(6 * 86400))

        await log.record(.gitHubFailed(status: 2), at: start.addingTimeInterval(8 * 86400))

        let written = try lines(url)
        #expect(written.count == 2)
        #expect(written.allSatisfy { $0.contains("gh failed") })
    }

    @Test func keepsToItsSize() async throws {
        let url = url()
        let log = DiagnosticLog(url: url)
        await log.setEnabled(true, at: start)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let line = "\(start.formatted(.iso8601))\tfiller \(String(repeating: "x", count: 200))\n"
        try Data(String(repeating: line, count: 4000).utf8).write(to: url)
        #expect(DiagnosticLog.size(of: url) > DiagnosticLog.sizeLimit)

        await log.record(.settingsProblem, at: start.addingTimeInterval(60))

        #expect(DiagnosticLog.size(of: url) <= DiagnosticLog.sizeLimit / 2 + 200)
        #expect(try lines(url).last?.hasSuffix("settings file could not be read or saved") == true)
    }

    @Test func aLineThatIsNotOursIsDropped() async throws {
        let url = url()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a dated line\n".utf8).write(to: url)
        let log = DiagnosticLog(url: url)

        await log.setEnabled(true, at: start)

        #expect(try lines(url).isEmpty)
    }

    @Test func eventsCannotCarryPathsOrSentences() {
        let event = DiagnosticEvent.shortcutRefused(action: "/Users/someone/Secret Project\nnew line")
        #expect(!event.line.contains("/"))
        #expect(!event.line.contains(" Project"))
        #expect(!event.line.contains("\n"))
    }

    @Test func theSizeOfNoFileIsZero() {
        #expect(DiagnosticLog.size(of: url()) == 0)
    }

    @Test func theLogLivesInTheUsersLogsFolder() {
        #expect(DiagnosticLog.defaultURL.path(percentEncoded: false)
            .hasSuffix("/Library/Logs/GlassWork/diagnostic.log"))
    }

    @Test func theSwitchSurvivesTheFile() throws {
        let file = SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
        var settings = AppSettings()
        settings.keepsDiagnosticLog = true
        try file.save(settings)
        #expect(try file.load()?.keepsDiagnosticLog == true)
    }
}
