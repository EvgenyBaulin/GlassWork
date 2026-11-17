import Foundation
@testable import GlassWorkCore
import Testing

struct DockFocusWidgetTests {
    @Test
    func dockOnlyModulesStayOutOfMenuBarAndShortcuts() {
        let ids: Set<ModuleID> = [.counter, .breathe, .screenTime]
        #expect(Set(ModuleID.allCases.filter(\.isDockOnly)) == ids)
        #expect(ids.isDisjoint(with: ModuleID.shortcutModules))
        #expect(ids.isSubset(of: Set(ModuleID.dockWidgets)))
        let settings = AppSettings()
        for id in ids {
            #expect(settings.module(id)?.mode == .off)
        }
    }

    @Test
    func counterCountsAndPersistsInOptions() {
        var settings = AppSettings()
        settings.updateCounter { $0.increment() }
        settings.updateCounter { $0.increment() }
        settings.updateCounter { $0.decrement() }
        settings.updateCounter { $0.title = "Coffee" }
        let state = CounterState(options: settings.module(.counter)?.options ?? [:])
        #expect(state.value == 1)
        #expect(state.title == "Coffee")
        settings.updateCounter { $0.reset() }
        #expect(settings.module(.counter)?.options[CounterState.valueKey] == nil)
        #expect(settings.module(.counter)?.options[CounterState.titleKey] == "Coffee")
    }

    @Test
    func counterIsBoundedAndReadsBadOptions() {
        var state = CounterState(options: [CounterState.valueKey: "999999"])
        state.increment()
        #expect(state.value == CounterState.limit)
        #expect(CounterState(options: [CounterState.valueKey: "many"]).value == 0)
        #expect(CounterState(options: [CounterState.valueKey: "-5"]).value == -5)
        state.title = String(repeating: "x", count: 100)
        var options: [String: String] = [:]
        state.write(to: &options)
        #expect(options[CounterState.titleKey]?.count == CounterState.maxTitleLength)
    }

    @Test
    func clickCountsOnlyWhenAsked() {
        let off = DockWidgetContext()
        let counting = DockWidgetContext(countsOnClick: true)
        #expect(DockWidgetClick.resolve(.counter, context: off, at: Date()) == .showCard)
        #expect(DockWidgetClick.resolve(.counter, context: counting, at: Date()) == .incrementCounter)
        #expect(DockWidgetClick.resolve(.breathe, context: counting, at: Date()) == .showCard)
    }

    @Test
    func breathingFollowsFourFourSix() {
        let cycle = BreathingCycle()
        #expect(cycle.length == 14)
        #expect(cycle.moment(at: 0) == .init(phase: .inhale, secondsLeft: 4, fullness: 0))
        #expect(cycle.moment(at: 2).fullness == 0.5)
        #expect(cycle.moment(at: 3.5).secondsLeft == 1)
        #expect(cycle.moment(at: 4) == .init(phase: .hold, secondsLeft: 4, fullness: 1))
        #expect(cycle.moment(at: 7.9).phase == .hold)
        #expect(cycle.moment(at: 8).phase == .exhale)
        #expect(cycle.moment(at: 11).fullness == 0.5)
        // The next breath starts over.
        #expect(cycle.moment(at: 14).phase == .inhale)
        #expect(cycle.moment(at: -3).phase == .inhale)
    }

    @Test
    func sessionEndsAfterItsMinutes() {
        let session = BreathingSession(options: [BreathingSession.minutesKey: "1"])
        #expect(session.duration == 60)
        #expect(session.moment(at: 59.9) != nil)
        #expect(session.moment(at: 60) == nil)
        #expect(session.remaining(at: 45) == 15)
        #expect(session.remaining(at: 100) == 0)
        #expect(BreathingSession(options: [BreathingSession.minutesKey: "7"]).minutes == 3)
        #expect(BreathingSession(options: [:]).minutes == 3)
        let swell = BreathingSession.idleFullness(at: Date(timeIntervalSinceReferenceDate: 5))
        #expect(abs(swell - 1) < 0.0001)
    }

    @Test
    func screenTimeSummaryReadsTodayAndWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar(identifier: .gregorian)
        var log = ScreenTimeLog()
        log.record(app: "Xcode", seconds: 3600, at: now.addingTimeInterval(-86400), calendar: calendar)
        log.record(app: "Xcode", seconds: 5400, at: now, calendar: calendar)
        log.record(app: "Safari", seconds: 1800, at: now, calendar: calendar)
        let summary = ScreenTimeSummary(log: log, at: now, calendar: calendar)
        #expect(summary.today == 7200)
        #expect(summary.tileText == "2h 0m")
        #expect(summary.topApps.map(\.name) == ["Xcode", "Safari"])
        #expect(summary.week.days.count == 7)
        #expect(summary.week.total == 10800)
        let empty = ScreenTimeSummary(log: ScreenTimeLog(), at: now, calendar: calendar)
        #expect(!empty.hasData)
        #expect(empty.tileText == "–")
    }
}
