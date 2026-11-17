import Foundation
@testable import GlassWorkCore
import Testing

struct OnboardingSetsTests {
    @Test func aSetRaisesOffModulesAndKeepsTheMenuBar() {
        var settings = AppSettings()
        settings.update(.git) { $0.mode = .hubOnly }
        settings.update(.docker) { $0.mode = .menuBar }
        OnboardingSet.apply([.developer], to: &settings)
        #expect(settings.module(.git)?.mode == .menuBar)
        #expect(settings.module(.devServers)?.mode == .menuBar)
        #expect(settings.module(.docker)?.mode == .menuBar)
        #expect(settings.module(.ping)?.mode == .hubOnly)
    }

    @Test func aModuleIsNeverLowered() {
        var settings = AppSettings()
        settings.update(.ping) { $0.mode = .menuBar }
        OnboardingSet.apply([.developer], to: &settings)
        #expect(settings.module(.ping)?.mode == .menuBar)
    }

    @Test func unpickedSetsAreUntouched() {
        var settings = AppSettings()
        let before = settings
        OnboardingSet.apply([.day], to: &settings)
        for id in ModuleID.allCases where id.group != .yourDay {
            #expect(settings.module(id) == before.module(id))
        }
        #expect(settings.module(.calendar)?.mode == .menuBar)
    }

    @Test func nothingPickedChangesNothing() {
        var settings = AppSettings()
        OnboardingSet.apply([], to: &settings)
        #expect(settings == AppSettings())
    }

    @Test func permissionsComeFromTheChosenSetsOnly() {
        let settings = AppSettings()
        #expect(OnboardingSet.permissions(of: [.day], in: settings) == [.calendars, .notifications])
        #expect(OnboardingSet.permissions(of: [.developer], in: settings) == [.notifications])
        #expect(OnboardingSet.permissions(of: [.mac], in: settings).isEmpty)
        #expect(OnboardingSet.permissions(of: [], in: settings).isEmpty)
    }
}

struct AutoUpdateTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)))
    }

    @Test func nextCheckIsTheNextNoon() throws {
        #expect(try AutoUpdate.nextCheck(after: date(17, 9), calendar: calendar) == date(17, 12))
        #expect(try AutoUpdate.nextCheck(after: date(17, 12), calendar: calendar) == date(18, 12))
        #expect(try AutoUpdate.nextCheck(after: date(17, 15), calendar: calendar) == date(18, 12))
    }

    @Test func nextBuildWaitsFiveDays() throws {
        let last = try date(10, 12, 30)
        #expect(try AutoUpdate.nextBuild(lastBuild: last, now: date(11, 8), calendar: calendar) == date(16, 12))
        // Overdue builds happen at the next check.
        #expect(try AutoUpdate.nextBuild(lastBuild: last, now: date(20, 8), calendar: calendar) == date(20, 12))
    }

    @Test func aBuildExactlyFiveDaysOldIsDueAtThatNoon() throws {
        let last = try date(10, 12)
        #expect(try AutoUpdate.nextBuild(lastBuild: last, now: date(11, 8), calendar: calendar) == date(15, 12))
    }

    @Test func noBuildOnRecordMeansTheNextCheck() throws {
        #expect(try AutoUpdate.nextBuild(lastBuild: nil, now: date(17, 9), calendar: calendar) == date(17, 12))
    }

    @Test func statusLeavesOutTheRebuildWhenOff() throws {
        let off = try AutoUpdate.status(isInstalled: false, lastBuild: nil, now: date(17, 9), calendar: calendar)
        #expect(off.nextBuild == nil)
        #expect(try off.nextCheck == date(17, 12))
    }

    @Test func pathsMatchTheScript() {
        let home = URL(filePath: "/Users/x")
        let agent = "/Users/x/Library/LaunchAgents/io.github.evgenybaulin.glasswork.autoupdate.plist"
        #expect(AutoUpdate.agentURL(home: home).path == agent)
        #expect(AutoUpdate.stampURL(home: home).lastPathComponent == "last-build")
        #expect(AutoUpdate.logURL(home: home).lastPathComponent == "auto-update.log")
    }
}
