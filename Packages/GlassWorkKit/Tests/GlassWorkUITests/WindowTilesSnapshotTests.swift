@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct WindowTilesTextTests {
    @Test func everyLayoutHasItsOwnTitle() {
        let titles = TileLayout.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func everyPlaceHasItsOwnTitle() {
        let titles = TileTarget.all.map(\.title)
        #expect(Set(titles).count == titles.count)
    }

    @Test func aHalfPressedAgainSaysWhatItBecame() {
        #expect(TileTarget(.leftHalf).title == TileLayout.leftHalf.title)
        #expect(TileTarget(.leftHalf, step: 1).title != TileLayout.leftHalf.title)
    }

    @Test func thePreviewOfADisplayMoveNamesTheMove() {
        let display = TileDisplay(frame: .zero, visibleFrame: .zero)
        let tiled = TilePlan(frame: .zero, display: display, tile: TileTarget(.rightHalf, step: 2))
        #expect(TileCommand.place(.rightHalf).title(for: tiled) == TileTarget(.rightHalf, step: 2).title)
        #expect(TileCommand.nextDisplay.title(for: tiled) == TileCommand.nextDisplay.title)
    }

    @Test func onlyThePermissionMessageExplainsAnything() {
        let others: [WindowTilesNotice] = [.noWindow, .cannotMove, .fullScreen, .oneDisplay]
        #expect(WindowTilesNotice.needsAccessibility.detail != nil)
        for notice in others {
            #expect(notice.detail == nil)
            #expect(WindowTilesNotice.needsAccessibility.duration > notice.duration)
        }
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct WindowTilesSnapshotTests {
    private func pane(enabled: Bool, trusted: Bool, taken: [String] = []) -> some View {
        WindowTilesPane(
            isEnabled: .constant(enabled),
            showsPreview: .constant(true),
            isTrusted: trusted,
            takenShortcuts: taken,
            openAccessibilitySettings: {}
        )
    }

    @Test(arguments: [true, false])
    func offAsOnFirstLaunch(dark: Bool) {
        assertPanel(pane(enabled: false, trusted: false), width: 680, height: 640, dark: dark, name: "pane-off")
    }

    @Test(arguments: [true, false])
    func onWithAccess(dark: Bool) {
        assertPanel(pane(enabled: true, trusted: true), width: 680, height: 640, dark: dark, name: "pane-on")
    }

    @Test(arguments: [true, false])
    func onWithoutAccessSaysWhatToDo(dark: Bool) {
        assertPanel(pane(enabled: true, trusted: false), width: 680, height: 700, dark: dark, name: "pane-no-access")
    }

    @Test(arguments: [true, false])
    func namesShortcutsAnotherAppTook(dark: Bool) {
        let view = pane(enabled: true, trusted: true, taken: ["⌃⌥C", "⌃⌥K"])
        assertPanel(view, width: 680, height: 700, dark: dark, name: "pane-taken")
    }

    /// The narrowest the window goes: the grid drops to three columns.
    @Test(arguments: [true, false])
    func fitsTheSmallestWindow(dark: Bool) {
        assertPanel(pane(enabled: true, trusted: true), width: 540, height: 700, dark: dark, name: "pane-narrow")
    }

    @Test(arguments: [true, false])
    func previewOfAHalf(dark: Bool) {
        let view = WindowTilesPreview(title: TileLayout.leftHalf.title, shortcut: "⌃⌥←")
        assertPanel(view, width: 756, height: 596, dark: dark, name: "preview-left-half")
    }

    @Test(arguments: [true, false])
    func labelAlone(dark: Bool) {
        snapshotPanel(
            WindowTilesLabel(title: TileLayout.leftHalf.title, shortcut: "⌃⌥←").padding(40),
            name: "label",
            dark: dark
        )
    }

    @Test(arguments: [true, false])
    func noticeWithInstructions(dark: Bool) {
        snapshotPanel(WindowTilesNoticeHUD(notice: .needsAccessibility), name: "notice-access", dark: dark)
    }

    @Test(arguments: [true, false])
    func shortNotice(dark: Bool) {
        snapshotPanel(WindowTilesNoticeHUD(notice: .noWindow), name: "notice-no-window", dark: dark)
    }
}
