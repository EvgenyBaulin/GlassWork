import Foundation
@testable import GlassWorkCore
import Testing

struct TimeMachineTests {
    @Test func idleReportsNothingRunning() throws {
        #expect(try TimeMachineParser.progress(fixture("tmutil-status-idle.plist")) == .idle)
    }

    @Test func runningReportsProgressAndTimeLeft() throws {
        let state = try TimeMachineParser.progress(fixture("tmutil-status-running-handmade.plist"))
        #expect(state == .running(progress: 0.42, secondsLeft: 540))
    }

    @Test func aNegativePercentMeansStillPreparing() {
        let plist = """
        <plist version="1.0"><dict><key>Running</key><true/><key>Percent</key><real>-1</real></dict></plist>
        """
        #expect(TimeMachineParser.progress(Data(plist.utf8)) == .running(progress: nil, secondsLeft: nil))
    }

    @Test func destinationIsTheFirstDisk() throws {
        #expect(try TimeMachineParser.destination(fixture("tmutil-destinationinfo.plist")) == "Macintosh HD")
    }

    @Test func preferencesGiveTheLastActivityInLocalTime() throws {
        let preferences = try #require(try TimeMachineParser.preferences(fixture("timemachine-preferences.plist")))
        let expected = DateComponents(
            calendar: .current, year: 2024, month: 11, day: 4, hour: 15, minute: 27, second: 15
        ).date
        #expect(preferences.last == expected)
        #expect(preferences.isAutomatic == false)
        #expect(preferences.backups.isEmpty)
    }

    /// The Mac these came from last touched Time Machine in 2024, which must not read as a fresh backup.
    @Test func anOldActivityIsOverdueAndUnconfirmed() throws {
        let preferences = try TimeMachineParser.preferences(fixture("timemachine-preferences.plist"))
        let status = TimeMachineParser.status(running: .idle, destination: "Macintosh HD", preferences: preferences)
        let now = DateComponents(calendar: .current, year: 2026, month: 11, day: 4).date ?? Date()

        #expect(status.isOverdue(at: now))
        #expect(status.isConfirmed == false)
    }

    @Test func aRecentBackupIsNotOverdue() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let status = TimeMachineStatus(state: .idle, lastBackup: now.addingTimeInterval(-86400), backups: [now])
        #expect(status.isOverdue(at: now) == false)
        #expect(status.isConfirmed)
    }

    @Test func noDiskMeansNotConfigured() {
        let status = TimeMachineParser.status(running: .idle, destination: nil, preferences: nil)
        #expect(status.state == .notConfigured)
    }

    @Test func aDiskWithUnreadablePreferencesNeedsPermission() {
        let status = TimeMachineParser.status(running: .idle, destination: "Backup", preferences: nil)
        #expect(status.state == .needsPermission)
        #expect(status.destination == "Backup")
    }

    @Test func aRunningBackupWinsOverMissingPermission() {
        let running = TimeMachineStatus.State.running(progress: 0.5, secondsLeft: nil)
        let status = TimeMachineParser.status(running: running, destination: "Backup", preferences: nil)
        #expect(status.state == running)
    }

    @Test func daysMarkEveryDayWithABackup() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = now.addingTimeInterval(-86400)
        let status = TimeMachineStatus(state: .idle, lastBackup: now, backups: [yesterday])

        let days = status.days(3, at: now, calendar: calendar)

        #expect(days.map(\.backedUp) == [false, true, true])
    }
}
