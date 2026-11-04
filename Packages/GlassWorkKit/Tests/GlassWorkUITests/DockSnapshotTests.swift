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

    private func dock(
        space: DockSpace,
        pointer: Double? = nil,
        running: Set<String> = [],
        position: DockPosition = .bottom
    ) -> some View {
        var settings = settings
        settings.position = position
        let state = DockLiveState(settings: settings)
        state.running = running
        let size = DockBarLayout.windowSize(for: space, count: apps.count, settings: settings)
        let view = DockView(
            state: state,
            monitor: SystemMonitor(),
            actions: DockActions(
                open: { _ in },
                clickWidget: { _ in },
                holdWidget: { _ in },
                update: { _ in },
                needsSpace: { _ in }
            ),
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

    /// The running dots sit on the side of the screen's edge.
    @Test(arguments: [true, false])
    func onTheLeft(dark: Bool) {
        let running = Set(apps.prefix(2).map(\.path))
        snapshotPanel(dock(space: .rest, running: running, position: .left), name: "left", dark: dark)
    }

    @Test(arguments: [true, false])
    func onTheRight(dark: Bool) {
        let running = Set(apps.prefix(2).map(\.path))
        snapshotPanel(dock(space: .rest, running: running, position: .right), name: "right", dark: dark)
    }

    /// Icons grow away from the screen's edge.
    @Test(arguments: [true, false])
    func magnifiedOnTheLeft(dark: Bool) {
        snapshotPanel(dock(space: .magnified, pointer: 0, position: .left), name: "left-middle", dark: dark)
    }

    @Test(arguments: [true, false])
    func magnifiedOnTheRight(dark: Bool) {
        snapshotPanel(dock(space: .magnified, pointer: 0, position: .right), name: "right-middle", dark: dark)
    }

    /// A widget keeps its slot's size and leaves the dot's place empty, so it lines up with the apps.
    @Test(arguments: [true, false])
    func widgetsBesideApps(dark: Bool) {
        let monitor = SystemMonitor()
        let row = HStack(alignment: .bottom, spacing: 8) {
            AppTile(app: apps[0], size: 48, isRunning: true) {}
            WidgetTile(module: .cpu, size: 48, monitor: monitor, click: {}, hold: {})
            WidgetTile(module: .memory, size: 48, monitor: monitor, click: {}, hold: {})
        }
        .padding(8)
        snapshotPanel(row, name: "widgets", dark: dark)
    }

    @Test(arguments: [true, false])
    func firstRunExplanation(dark: Bool) {
        snapshotPanel(DockFirstRunView(proceed: {}, cancel: {}), name: "first-run", dark: dark)
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
