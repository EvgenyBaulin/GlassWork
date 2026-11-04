import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct QuickQuitKeyTests {
    @Test
    func returnQuits() {
        #expect(QuickQuitKey(keyCode: 36, isOptionDown: false) == .quit)
        #expect(QuickQuitKey(keyCode: 76, isOptionDown: false) == .quit)
    }

    @Test
    func optionReturnForceQuits() {
        #expect(QuickQuitKey(keyCode: 36, isOptionDown: true) == .forceQuit)
    }

    @Test
    func arrowsMove() {
        #expect(QuickQuitKey(keyCode: 126, isOptionDown: false) == .previous)
        #expect(QuickQuitKey(keyCode: 125, isOptionDown: false) == .next)
    }

    @Test
    func typingIsLeftToTheField() {
        #expect(QuickQuitKey(keyCode: 0, isOptionDown: false) == nil)
        #expect(QuickQuitKey(keyCode: 53, isOptionDown: false) == nil)
    }
}

@MainActor
struct QuickQuitStateTests {
    private final class Calls {
        var quits: [(name: String, force: Bool)] = []
    }

    private struct Palette {
        let state: QuickQuitState
        let store: AppUsageStore
        let calls: Calls
    }

    private func make(
        apps: [AppUsage] = AppSamples.apps,
        query: String = ""
    ) -> Palette {
        let store = AppUsageStore()
        store.show(apps)
        let calls = Calls()
        let state = QuickQuitState(store: store, query: query) { calls.quits.append(($0.name, $1)) }
        return Palette(state: state, store: store, calls: calls)
    }

    @Test
    func returnQuitsTheFirstMatch() {
        let palette = make(query: "sl")
        palette.state.handle(.quit)
        #expect(palette.calls.quits.map(\.name) == ["Slack"])
        #expect(palette.calls.quits.first?.force == false)
    }

    @Test
    func optionReturnForceQuitsIt() {
        let palette = make(query: "sl")
        palette.state.handle(.forceQuit)
        #expect(palette.calls.quits.first?.force == true)
    }

    @Test
    func arrowsChooseAnotherRowAndStopAtTheEnds() {
        let palette = make()
        let state = palette.state
        state.handle(.previous)
        #expect(state.highlighted?.name == "Xcode")
        state.handle(.next)
        #expect(state.highlighted?.name == "Safari")
        for _ in 0 ..< 20 {
            state.handle(.next)
        }
        #expect(state.highlighted?.id == state.results.last?.id)
        #expect(palette.calls.quits.isEmpty)
    }

    @Test
    func typingGoesBackToTheFirstRow() {
        let state = make().state
        state.handle(.next)
        state.query = "s"
        #expect(state.highlighted?.name == "Safari")
    }

    @Test
    func noMatchesQuitsNothing() {
        let palette = make(query: "zzz")
        palette.state.handle(.quit)
        palette.state.handle(.forceQuit)
        #expect(palette.calls.quits.isEmpty)
    }

    @Test
    func systemAppsAndGlassWorkAreNotOffered() {
        let finder = AppUsage(
            id: "com.apple.finder",
            pid: 100_100,
            name: "Finder",
            bundleID: "com.apple.finder",
            path: "/System/Library/CoreServices/Finder.app",
            cpu: 1,
            memory: 9_000_000_000
        )
        let own = AppUsage(id: "own", pid: 100_101, name: "GlassWork", cpu: 1, memory: 9_000_000_000)
        let state = make(apps: AppSamples.apps + [finder, own]).state
        #expect(!state.results.contains { $0.name == "Finder" || $0.name == "GlassWork" })
    }

    @Test
    func rowsHoldStillWhenFiguresChange() {
        let palette = make()
        var apps = AppSamples.apps
        apps[1].memory = 99_000_000_000
        palette.store.show(apps)
        #expect(palette.state.results.first?.name == "Xcode")
        #expect(palette.state.results[1].memory == 99_000_000_000)
    }

    @Test
    func aQuitAppLeavesTheHighlight() {
        let palette = make()
        palette.state.handle(.next)
        palette.store.show(AppSamples.apps.filter { $0.name != "Safari" })
        #expect(palette.state.highlighted?.name == "Xcode")
    }

    @Test
    func theListStaysShort() {
        let many = (0 ..< 20)
            .map { AppUsage(id: "\($0)", pid: Int32(100_200 + $0), name: "App \($0)", cpu: 0, memory: 1) }
        #expect(make(apps: many).state.results.count == 6)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct QuickQuitSnapshotTests {
    private func palette(query: String) -> some View {
        let store = AppUsageStore()
        store.show(AppSamples.apps)
        return QuickQuitView(state: QuickQuitState(store: store, query: query) { _, _ in })
    }

    @Test(arguments: [true, false])
    func searching(dark: Bool) {
        snapshotPanel(palette(query: "sl"), name: "searching", dark: dark)
    }

    @Test(arguments: [true, false])
    func heaviestFirstBeforeTyping(dark: Bool) {
        snapshotPanel(palette(query: ""), name: "all", dark: dark)
    }

    @Test(arguments: [true, false])
    func nothingFound(dark: Bool) {
        snapshotPanel(palette(query: "zzz"), name: "none", dark: dark)
    }
}
