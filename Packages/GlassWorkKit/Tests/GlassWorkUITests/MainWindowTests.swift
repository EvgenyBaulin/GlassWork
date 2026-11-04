import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct RouteHistoryTests {
    private let apps = MainRoute(section: .apps)
    private let dock = MainRoute(section: .dock)
    private let unlock = MainRoute(section: .unlock)

    @Test
    func startsWithNowhereToGo() {
        let history = RouteHistory(start: apps)
        #expect(history.current == apps)
        #expect(!history.canGoBack)
        #expect(!history.canGoForward)
    }

    @Test
    func walksBackAndForward() {
        var history = RouteHistory(start: apps)
        history.go(to: dock)
        history.goBack()
        #expect(history.current == apps)
        #expect(history.canGoForward)
        history.goForward()
        #expect(history.current == dock)
    }

    @Test
    func goingSomewhereNewDropsWhatLayAhead() {
        var history = RouteHistory(start: apps)
        history.go(to: dock)
        history.goBack()
        history.go(to: unlock)
        #expect(!history.canGoForward)
        #expect(history.routes == [apps, unlock])
    }

    @Test
    func theSamePlaceIsNotAStep() {
        var history = RouteHistory(start: apps)
        history.go(to: apps)
        #expect(!history.canGoBack)
    }

    @Test
    func keepsALimitedTrail() {
        var history = RouteHistory(start: apps)
        for index in 0 ..< 200 {
            history.go(to: index.isMultiple(of: 2) ? dock : unlock)
        }
        #expect(history.routes.count == 50)
        #expect(history.current == history.routes.last)
    }

    @Test
    func anItemShowsInTheTitle() {
        let route = MainRoute(section: .dock, item: .init(id: "x", title: "Xcode"))
        #expect(route.title.hasSuffix("› Xcode"))
    }
}

struct MainSectionTests {
    @Test
    func theSidebarFollowsTheDesign() {
        #expect(MainSection.allCases == [
            .overview, .apps, .clipboard, .windowTiles, .unlock, .widgets, .dock, .settings,
        ])
    }

    @Test
    func onlySettingsLeavesTheWindow() {
        #expect(MainSection.allCases.filter(\.opensOwnWindow) == [.settings])
    }

    @Test
    func choosingSomethingTellsTheApp() async {
        await MainActor.run {
            let navigation = MainNavigation(start: MainRoute(section: .apps))
            var changes = 0
            navigation.onChange = { changes += 1 }
            navigation.go(to: MainRoute(section: .dock))
            navigation.goBack()
            #expect(changes == 2)
            #expect(navigation.route.section == .apps)
        }
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct MainWindowSnapshotTests {
    @Test(arguments: [true, false])
    func placeholder(dark: Bool) {
        let view = SectionPlaceholder(.overview).frame(width: 640, height: 300)
        snapshotPanel(view, name: "placeholder", dark: dark)
    }

    @Test(arguments: [true, false])
    func unlock(dark: Bool) {
        let view = SectionPlaceholder(
            .unlock,
            heading: "Unlock this Mac",
            note: "How this will work is not decided yet.",
            title: "To be designed",
            detail: "Nothing here stores your password until the method and its risks are agreed."
        )
        .frame(width: 640, height: 300)
        snapshotPanel(view, name: "unlock", dark: dark)
    }

    @Test(arguments: [true, false])
    func sidebar(dark: Bool) {
        let rows = VStack(alignment: .leading, spacing: 10) {
            ForEach(MainSection.allCases) { MainSidebarRow(section: $0) }
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        snapshotPanel(rows, name: "sidebar", dark: dark)
    }
}
