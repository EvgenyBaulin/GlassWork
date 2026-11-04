import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockSnapshotTests {
    private let apps = (0 ..< 7).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }

    private var settings: DockSettings {
        var settings = DockSettings()
        settings.iconSize = 48
        settings.magnifies = true
        settings.magnifiedSize = 80
        settings.items = apps.map(DockItem.app)
        return settings
    }

    private func dock(space: DockSpace, pointer: Double? = nil, running: Set<String> = []) -> some View {
        let state = DockLiveState(settings: settings)
        state.running = running
        let size = DockBarLayout.windowSize(for: space, count: apps.count, settings: settings)
        let view = DockView(
            state: state,
            monitor: SystemMonitor(),
            actions: DockActions(open: { _ in }, showPanel: { _ in }, update: { _ in }, needsSpace: { _ in }),
            pointer: pointer
        )
        return view.frame(width: size.width, height: size.height)
    }

    @Test(arguments: [true, false])
    func rest(dark: Bool) {
        snapshotPanel(dock(space: .rest), name: "rest", dark: dark)
    }

    @Test(arguments: [true, false])
    func magnifiedInTheMiddle(dark: Bool) {
        snapshotPanel(dock(space: .magnified, pointer: 0), name: "middle", dark: dark)
    }

    @Test(arguments: [true, false])
    func magnifiedAtTheEdge(dark: Bool) {
        snapshotPanel(dock(space: .magnified, pointer: -180), name: "edge", dark: dark)
    }

    /// Not running, running, and a launch at the top of its jump.
    @Test(arguments: [true, false])
    func appStates(dark: Bool) {
        let row = HStack(alignment: .bottom, spacing: 8) {
            AppTile(app: apps[0], size: 48, isRunning: false) {}
            AppTile(app: apps[1], size: 48, isRunning: true) {}
            AppTile(app: apps[2], size: 48, isRunning: false, isLaunching: true, pose: 1) {}
        }
        .padding(8)
        .padding(.top, 24)
        snapshotPanel(row, name: "states", dark: dark)
    }
}
