import Foundation
@testable import GlassWorkCore
import Testing

struct RestartGuardTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    @Test func aLaunchAfterANormalQuitAlwaysRuns() {
        var guardian = RestartGuard()
        for minute in 0 ..< 10 {
            #expect(guardian.launch(at: minutes(Double(minute)), byKeeper: true) == .run)
            guardian.quit()
        }
        #expect(guardian.restarts.isEmpty)
    }

    @Test func givesUpOnTheFourthCrashInTenMinutes() {
        var guardian = RestartGuard()
        #expect(guardian.launch(at: minutes(0), byKeeper: true) == .run)
        // Each later launch by launchd follows a run that never quit: a crash.
        #expect(guardian.launch(at: minutes(1), byKeeper: true) == .run)
        #expect(guardian.launch(at: minutes(2), byKeeper: true) == .run)
        #expect(guardian.launch(at: minutes(3), byKeeper: true) == .run)
        #expect(guardian.launch(at: minutes(4), byKeeper: true) == .giveUp)
    }

    @Test func crashesFarApartDoNotAddUp() {
        var guardian = RestartGuard()
        #expect(guardian.launch(at: minutes(0), byKeeper: true) == .run)
        for hour in 1 ... 6 {
            #expect(guardian.launch(at: minutes(Double(hour) * 11), byKeeper: true) == .run)
        }
    }

    @Test func openingTheAppByHandStartsAfresh() {
        var guardian = RestartGuard()
        _ = guardian.launch(at: minutes(0), byKeeper: true)
        for minute in 1 ... 3 {
            _ = guardian.launch(at: minutes(Double(minute)), byKeeper: true)
        }
        #expect(guardian.launch(at: minutes(4), byKeeper: true) == .giveUp)
        #expect(guardian.launch(at: minutes(5), byKeeper: false) == .run)
        #expect(guardian.restarts.isEmpty)
    }

    @Test func survivesAClockThatWentBack() {
        var guardian = RestartGuard()
        _ = guardian.launch(at: minutes(30), byKeeper: true)
        _ = guardian.launch(at: minutes(31), byKeeper: true)
        #expect(guardian.launch(at: minutes(0), byKeeper: true) == .run)
        #expect(guardian.restarts == [minutes(0)])
    }
}
