import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockTrashRecentsSnapshotTests {
    private let apps = (0 ..< 3).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }
    private let recents = (3 ..< 5).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }

    private func dock(
        full: Bool = false,
        showsRecents: Bool = false,
        showsIndicators: Bool = true
    ) -> some View {
        var settings = DockSettings()
        settings.iconSize = 48
        settings.showsRecents = showsRecents
        settings.showsTrash = true
        settings.showsRunningIndicators = showsIndicators
        settings.items = apps.map(DockItem.app)
        let state = DockLiveState(settings: settings)
        state.trashIsFull = full
        state.recentApps = recents
        state.running = Set(apps.prefix(2).map(\.path))
        let count = state.arrangement.slots.count
        let size = DockBarLayout.windowSize(for: .rest, count: count, settings: settings)
        let view = DockView(
            state: state,
            monitor: SystemMonitor(),
            actions: DockActions(
                open: { _ in },
                clickWidget: { _ in },
                holdWidget: { _ in },
                update: { _ in },
                needsSpace: { _ in }
            )
        )
        return view.frame(width: size.width, height: size.height)
    }

    @Test(arguments: [true, false])
    func emptyTrash(dark: Bool) {
        let tile = TrashTile(isFull: false, size: 48) {}.padding(8)
        snapshotPanel(tile, name: "trash-empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func fullTrash(dark: Bool) {
        let tile = TrashTile(isFull: true, size: 48) {}.padding(8)
        snapshotPanel(tile, name: "trash-full", dark: dark)
    }

    @Test(arguments: [true, false])
    func dockWithRecents(dark: Bool) {
        snapshotPanel(dock(full: true, showsRecents: true), name: "recents", dark: dark)
    }

    @Test(arguments: [true, false])
    func hiddenRunningIndicators(dark: Bool) {
        snapshotPanel(dock(showsIndicators: false), name: "no-indicators", dark: dark)
    }
}
