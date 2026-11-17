import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// The Counter, Breathe and Screen Time widgets of the Dock: their tiles and cards, in both themes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockFocusSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func actions(_ options: [ModuleID: [String: String]]) -> PanelActions {
        PanelActions(moduleOptions: { options[$0] ?? [:] })
    }

    private var counterOptions: [String: String] {
        [CounterState.valueKey: "12", CounterState.titleKey: "Coffee", CounterState.countsOnClickKey: "true"]
    }

    private func tile(_ module: ModuleID, log: ScreenTimeLog? = nil, options: [ModuleID: [String: String]] = [:])
        -> some View
    {
        WidgetTile(
            module: module,
            size: 56,
            monitor: SystemMonitor(),
            animates: false,
            screenTimeLog: log,
            click: {},
            hold: {}
        )
        .environment(\.panelActions, actions(options))
        .padding(8)
    }

    /// A day with 1 h 30 min today and a week behind it.
    private var log: ScreenTimeLog {
        var log = ScreenTimeLog()
        for back in 0 ..< 7 {
            let day = Self.now.addingTimeInterval(-Double(back) * 86400)
            log.record(app: "Xcode", seconds: Double(2400 + back * 900), at: day)
            log.record(app: "Safari", seconds: 1500, at: day)
        }
        log.recordBreak(from: Self.now.addingTimeInterval(-3000), to: Self.now.addingTimeInterval(-1500))
        return log
    }

    @Test(arguments: [true, false])
    func counterTile(dark: Bool) {
        let view = tile(.counter, options: [.counter: counterOptions])
        assertPanel(view, width: 72, height: 72, dark: dark, name: "dock-counter-tile")
    }

    @Test(arguments: [true, false])
    func breatheTile(dark: Bool) {
        assertPanel(tile(.breathe), width: 72, height: 72, dark: dark, name: "dock-breathe-tile")
    }

    @Test(arguments: [true, false])
    func screenTimeTile(dark: Bool) {
        var today = ScreenTimeLog()
        today.record(app: "Xcode", seconds: 5400, at: Date())
        assertPanel(tile(.screenTime, log: today), width: 72, height: 72, dark: dark, name: "dock-screentime-tile")
    }

    @Test(arguments: [true, false])
    func counterCard(dark: Bool) {
        let card = CounterPanel().environment(\.panelActions, actions([.counter: counterOptions]))
        assertPanel(card, dark: dark, name: "dock-counter-card")
    }

    @Test(arguments: [true, false])
    func breatheCardIdle(dark: Bool) {
        let card = BreathePanel().environment(\.panelActions, actions([.breathe: [BreathingSession.minutesKey: "5"]]))
        assertPanel(card, dark: dark, name: "dock-breathe-card")
    }

    @Test(arguments: [true, false])
    func breatheStageInhaling(dark: Bool) {
        let moment = BreathingCycle().moment(at: 1.5)
        let stage = BreathingStage(moment: moment, remaining: 150, isFinished: false).padding(14)
        assertPanel(stage, dark: dark, name: "dock-breathe-stage")
    }

    @Test(arguments: [true, false])
    func breatheStageFinished(dark: Bool) {
        let stage = BreathingStage(moment: nil, remaining: 0, isFinished: true).padding(14)
        assertPanel(stage, dark: dark, name: "dock-breathe-stage-done")
    }

    @Test(arguments: [true, false])
    func screenTimeCard(dark: Bool) {
        let card = ScreenTimeCard(summary: ScreenTimeSummary(log: log, at: Self.now))
        assertPanel(card, dark: dark, name: "dock-screentime-card")
    }

    @Test(arguments: [true, false])
    func screenTimeCardHovered(dark: Bool) {
        let summary = ScreenTimeSummary(log: log, at: Self.now)
        let card = ScreenTimeCard(summary: summary, chartHover: summary.week.days[4].date)
        assertPanel(card, dark: dark, name: "dock-screentime-card-hover")
    }

    @Test(arguments: [true, false])
    func screenTimeCardEmpty(dark: Bool) {
        let card = ScreenTimeCard(summary: ScreenTimeSummary(log: ScreenTimeLog(), at: Self.now))
        assertPanel(card, dark: dark, name: "dock-screentime-card-empty")
    }
}
