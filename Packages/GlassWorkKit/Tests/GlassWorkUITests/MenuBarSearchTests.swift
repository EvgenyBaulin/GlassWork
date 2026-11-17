import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct MenuBarSearchKeyTests {
    @Test
    func returnAndArrowsAreKeys() {
        #expect(MenuBarSearchKey(keyCode: 36) == .activate)
        #expect(MenuBarSearchKey(keyCode: 76) == .activate)
        #expect(MenuBarSearchKey(keyCode: 126) == .previous)
        #expect(MenuBarSearchKey(keyCode: 125) == .next)
    }

    @Test
    func typingAndEscapeAreLeftAlone() {
        #expect(MenuBarSearchKey(keyCode: 0) == nil)
        #expect(MenuBarSearchKey(keyCode: 53) == nil)
    }
}

@MainActor
private enum MenuBarSearchSamples {
    static let entries = [
        MenuBarEntry(pid: 90001, index: 0, appName: "Dropbox", title: nil, minX: 100, width: 28),
        MenuBarEntry(pid: 90002, index: 1, appName: "Bartender Helper", title: "Wi-Fi", minX: 160, width: 28),
        MenuBarEntry(pid: 90003, index: 0, appName: "Slack", title: nil, minX: 220, width: 28),
        MenuBarEntry(pid: 90004, index: 0, appName: "Clock", title: "Time", minX: 900, width: 60),
    ]

    final class Calls {
        var pressed: [String] = []
        var opened = 0
    }

    static func state(
        _ phase: MenuBarSearchState.Phase = .ready,
        query: String = "",
        calls: Calls = Calls()
    ) -> MenuBarSearchState {
        let state = MenuBarSearchState(
            phase: phase,
            query: query,
            onActivate: { calls.pressed.append($0.name) },
            onOpenSettings: { calls.opened += 1 }
        )
        if phase == .ready {
            state.load(entries, separatorMaxX: 500, alwaysHiddenMaxX: 130)
        }
        return state
    }
}

@MainActor
struct MenuBarSearchStateTests {
    @Test
    func onlyHiddenItemsAreListedClosestToTheClockFirst() {
        let state = MenuBarSearchSamples.state()
        #expect(state.results.map(\.appName) == ["Slack", "Bartender Helper", "Dropbox"])
    }

    @Test
    func showAllAddsTheVisibleOnes() {
        let state = MenuBarSearchSamples.state()
        state.showsAll = true
        #expect(state.results.count == 4)
    }

    @Test
    func sectionsComeFromTheSeparators() {
        let state = MenuBarSearchSamples.state()
        #expect(state.section(of: MenuBarSearchSamples.entries[0]) == .alwaysHidden)
        #expect(state.section(of: MenuBarSearchSamples.entries[2]) == .hidden)
        #expect(state.section(of: MenuBarSearchSamples.entries[3]) == .visible)
    }

    @Test
    func typingFilters() {
        let state = MenuBarSearchSamples.state(query: "wifi")
        #expect(state.results.isEmpty)
        state.query = "wi-"
        #expect(state.results.map(\.name) == ["Wi-Fi"])
    }

    @Test
    func returnActivatesTheFirstMatch() {
        let calls = MenuBarSearchSamples.Calls()
        let state = MenuBarSearchSamples.state(query: "s", calls: calls)
        state.handle(.activate)
        #expect(calls.pressed == ["Slack"])
    }

    @Test
    func arrowsMoveAndStopAtTheEnds() {
        let calls = MenuBarSearchSamples.Calls()
        let state = MenuBarSearchSamples.state(calls: calls)
        state.handle(.previous)
        #expect(state.highlighted?.appName == "Slack")
        state.handle(.next)
        state.handle(.next)
        state.handle(.next)
        #expect(state.highlighted?.appName == "Dropbox")
        state.handle(.activate)
        #expect(calls.pressed == ["Dropbox"])
    }

    @Test
    func changingTheQueryGoesBackToTheFirstRow() {
        let state = MenuBarSearchSamples.state()
        state.handle(.next)
        state.query = "d"
        #expect(state.highlighted?.appName == "Dropbox")
    }

    @Test
    func nothingIsActivatedWhileLoadingOrWithoutAccess() {
        for phase in [MenuBarSearchState.Phase.loading, .needsAccess] {
            let calls = MenuBarSearchSamples.Calls()
            let state = MenuBarSearchSamples.state(phase, calls: calls)
            state.handle(.activate)
            #expect(calls.pressed.isEmpty)
        }
    }

    @Test
    func theSettingsButtonReports() {
        let calls = MenuBarSearchSamples.Calls()
        MenuBarSearchSamples.state(.needsAccess, calls: calls).openSettings()
        #expect(calls.opened == 1)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct MenuBarSearchSnapshotTests {
    @Test(arguments: [true, false])
    func results(dark: Bool) {
        let view = MenuBarSearchView(state: MenuBarSearchSamples.state())
        snapshotPanel(view, name: "results", dark: dark)
    }

    @Test(arguments: [true, false])
    func showingAll(dark: Bool) {
        let state = MenuBarSearchSamples.state()
        state.showsAll = true
        snapshotPanel(MenuBarSearchView(state: state), name: "all", dark: dark)
    }

    @Test(arguments: [true, false])
    func empty(dark: Bool) {
        let view = MenuBarSearchView(state: MenuBarSearchSamples.state(query: "zzz"))
        snapshotPanel(view, name: "empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func noAccess(dark: Bool) {
        let view = MenuBarSearchView(state: MenuBarSearchSamples.state(.needsAccess))
        snapshotPanel(view, name: "no-access", dark: dark)
    }
}
