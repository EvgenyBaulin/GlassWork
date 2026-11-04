import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Sample apps. Their pids cannot exist, so the letter tiles stand in for icons on every Mac.
@MainActor
enum AppSamples {
    static let now = Date(timeIntervalSince1970: 1_800_000_000 / 600 * 600)

    static let apps = [
        sample("com.apple.dt.Xcode", 100_001, "Xcode", [24, 6.2, 9]),
        sample("com.apple.Safari", 100_002, "Safari", [11, 3.8, 6]),
        sample("com.figma.Desktop", 100_003, "Figma", [9, 2.1, 4]),
        sample("com.tinyspeck.slackmacgap", 100_004, "Slack", [3, 1.4, 3]),
        sample("com.apple.Music", 100_005, "Music", [2, 0.62, 1]),
        sample("com.apple.Notes", 100_006, "Notes", [0.4, 0.31, 1]),
        sample("com.apple.Terminal", 100_007, "Terminal", [0.2, 0.14, 0]),
    ]

    static var xcode: AppUsage {
        apps[0]
    }

    /// `use` holds CPU, gigabytes of memory and the number of helpers.
    private static func sample(
        _ id: String,
        _ pid: Int32,
        _ name: String,
        _ use: [Double]
    ) -> AppUsage {
        AppUsage(
            id: id,
            pid: pid,
            name: name,
            bundleID: id,
            path: "/Applications/\(name).app",
            cpu: use[0],
            memory: UInt64(use[1] * 1e9),
            helpers: Int(use[2])
        )
    }

    /// A day of a wavy line per app, ending at `now`.
    static var history: AppUsageHistory {
        var history = AppUsageHistory()
        let start = Int(now.timeIntervalSince1970) - 86400
        let records = stride(from: 0, to: 86400 - 3600, by: 600).map { offset in
            AppUsageRecord(time: start + offset, apps: Dictionary(uniqueKeysWithValues: apps.map { app in
                let wave = 1 + 0.6 * sin(Double(offset) / 7000)
                return (app.id, [app.cpu * wave, Double(app.memory) * (0.8 + 0.2 * wave)])
            }))
        }
        history.restore(records, now: now)
        for minute in 0 ... 60 {
            let wave = 1 + 0.5 * sin(Double(minute) / 5)
            let moment = now.addingTimeInterval(Double(minute - 60) * 60)
            history.record(apps.map { app in
                var app = app
                app.cpu *= wave
                app.memory = UInt64(Double(app.memory) * (0.85 + 0.15 * wave))
                return app
            }, at: moment)
        }
        return history
    }

    static func monitor(apps: [AppUsage] = AppSamples.apps) -> SystemMonitor {
        let monitor = SystemMonitor()
        monitor.apps.show(apps, history: history)
        return monitor
    }

    /// A moment on the charts, for the hover state.
    static var hoverMoment: Date {
        now.addingTimeInterval(-1800)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AppsSnapshotTests {
    private func section(hovered: AppUsage.ID? = nil, sparklineHover: Date? = nil) -> some View {
        AppsSection(
            monitor: AppSamples.monitor(),
            now: AppSamples.now,
            hoveredID: hovered,
            sparklineHover: sparklineHover
        ) { _ in }
            .frame(width: 660, height: 440)
    }

    private func detail(
        monitor: SystemMonitor = AppSamples.monitor(),
        range: AppHistoryRange = .day,
        hover: Date? = nil
    ) -> some View {
        AppDetail(
            id: AppSamples.xcode.id,
            name: "Xcode",
            monitor: monitor,
            range: range,
            now: AppSamples.now,
            hover: hover
        )
        .frame(width: 660, height: 590)
    }

    @Test(arguments: [true, false])
    func list(dark: Bool) {
        snapshotPanel(section(), name: "list", dark: dark)
    }

    @Test(arguments: [true, false])
    func rowUnderThePointer(dark: Bool) {
        snapshotPanel(section(hovered: AppSamples.xcode.id), name: "row-hover", dark: dark)
    }

    @Test(arguments: [true, false])
    func sparklineUnderThePointer(dark: Bool) {
        let view = section(hovered: AppSamples.xcode.id, sparklineHover: AppSamples.hoverMoment)
        snapshotPanel(view, name: "sparkline-hover", dark: dark)
    }

    @Test(arguments: [true, false])
    func oneApp(dark: Bool) {
        snapshotPanel(detail(), name: "detail", dark: dark)
    }

    @Test(arguments: [true, false])
    func chartsUnderThePointer(dark: Bool) {
        snapshotPanel(detail(hover: AppSamples.hoverMoment), name: "detail-hover", dark: dark)
    }

    @Test(arguments: [true, false])
    func anAppThatQuit(dark: Bool) {
        snapshotPanel(detail(monitor: AppSamples.monitor(apps: [])), name: "detail-gone", dark: dark)
    }

    @Test(arguments: [true, false])
    func noHistoryYet(dark: Bool) {
        let monitor = SystemMonitor()
        monitor.apps.show(AppSamples.apps)
        snapshotPanel(detail(monitor: monitor), name: "detail-empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func aSystemAppCannotBeQuit(dark: Bool) {
        var finder = AppSamples.xcode
        finder.name = "Finder"
        finder.path = "/System/Library/CoreServices/Finder.app"
        finder.bundleID = "com.apple.finder"
        snapshotPanel(detail(monitor: AppSamples.monitor(apps: [finder])), name: "detail-protected", dark: dark)
    }

    @Test(arguments: [true, false])
    func runningAppsBlock(dark: Bool) {
        let block = RunningAppsBlock(apps: AppSamples.apps, hoveredID: AppSamples.apps[1].id)
            .padding(12)
            .frame(width: 360)
        snapshotPanel(block, name: "hub-block", dark: dark)
    }

    @Test(arguments: [true, false])
    func optionTurnsQuitIntoForceQuit(dark: Bool) {
        let block = RunningAppsBlock(apps: AppSamples.apps, hoveredID: AppSamples.apps[1].id, startsForced: true)
            .padding(12)
            .frame(width: 360)
        snapshotPanel(block, name: "hub-block-forced", dark: dark)
    }

    @Test(arguments: [true, false])
    func topAppsByCPU(dark: Bool) {
        let list = TopApps(apps: AppSamples.apps, sort: .cpu, limit: 4, hoveredID: AppSamples.xcode.id)
            .padding(12)
            .frame(width: 340)
        snapshotPanel(list, name: "top-cpu", dark: dark)
    }
}

@MainActor
struct AppRowTests {
    @Test
    func aProtectedAppGetsNoQuitEvenUnderThePointer() {
        var app = AppSamples.xcode
        #expect(!app.isProtected)
        app.name = "Finder"
        #expect(app.isProtected)
    }
}
