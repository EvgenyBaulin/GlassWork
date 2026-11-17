import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockBadgeSnapshotTests {
    private let apps = (0 ..< 4).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }

    /// Plain, badged, past the cap, hidden, and asking for attention at the top of its pulse.
    @Test(arguments: [true, false])
    func appTilesWithBadgesAttentionAndHidden(dark: Bool) {
        let row = HStack(alignment: .bottom, spacing: 12) {
            AppTile(app: apps[0], size: 56, isRunning: true) {}
            AppTile(app: apps[1], size: 56, isRunning: true, tile: DockTileState(badge: "3")) {}
            AppTile(app: apps[2], size: 56, isRunning: true, tile: DockTileState(badge: "99+")) {}
            AppTile(app: apps[3], size: 56, isRunning: true, tile: DockTileState(isHidden: true)) {}
            AppTile(
                app: apps[0],
                size: 56,
                isRunning: true,
                tile: DockTileState(badge: "1", needsAttention: true),
                pulse: 1
            ) {}
        }
        .padding(20)
        snapshotPanel(row, name: "badges", dark: dark)
    }

    @Test(arguments: [true, false])
    func folderTileWithASummedBadge(dark: Bool) {
        let folder = AppFolder(name: "Work", apps: apps)
        let state = DockTileStates.state(for: folder, badges: [apps[0].path: "4", apps[1].path: "3"], attention: [])
        let row = HStack(spacing: 12) {
            FolderTile(folder: folder, size: 56, isRunning: false) {}
            FolderTile(folder: folder, size: 56, isRunning: true, tile: state) {}
        }
        .padding(20)
        snapshotPanel(row, name: "folder-badge", dark: dark)
    }
}
