import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct BatterySnapshotTests {
    private let states: [(name: String, sample: BatterySample)] = [
        ("discharging", BatterySample(charge: 0.62, isCharging: false, isOnAC: false)),
        ("charging", BatterySample(charge: 0.35, isCharging: true, isOnAC: true)),
        ("plugged", BatterySample(charge: 1, isCharging: false, isOnAC: true)),
        ("low", BatterySample(charge: 0.08, isCharging: false, isOnAC: false)),
    ]

    @Test(arguments: [true, false])
    func glyphStates(dark: Bool) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let rows = try states.map { state -> NSView in
            let strip = NSStackView()
            strip.orientation = .horizontal
            strip.spacing = 8
            for style in [DisplayStyle.symbol, .figure, .graph, .graphAndFigure] {
                let renderer = MenuBarItemRenderer(
                    module: .battery,
                    style: style,
                    numbers: .compact,
                    monitor: SystemMonitor()
                )
                renderer.appearance = appearance
                let content = ItemContent.battery(state.sample, style: .compact, options: [:])
                let width = MenuBarItemView.width(
                    module: .battery, style: style, numbers: .compact, monitor: SystemMonitor()
                )
                let size = CGSize(width: width, height: 24)
                let view = NSImageView(frame: CGRect(origin: .zero, size: size))
                view.image = try #require(renderer.image(content: content, size: size))
                view.contentTintColor = .labelColor
                view.widthAnchor.constraint(equalToConstant: width).isActive = true
                view.heightAnchor.constraint(equalToConstant: 24).isActive = true
                strip.addArrangedSubview(view)
            }
            return strip
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stack.appearance = appearance
        stack.wantsLayer = true
        stack.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        stack.frame = CGRect(origin: .zero, size: stack.fittingSize)
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: stack, as: .image(precision: 0.98), named: "glyphs-\(dark ? "dark" : "light")")
        }
    }

    private let apps = [
        AppUsage(id: "a", pid: 1, name: "Safari", cpu: 42, memory: 0),
        AppUsage(id: "b", pid: 2, name: "Xcode", cpu: 31.5, memory: 0),
        AppUsage(id: "c", pid: 3, name: "Slack", cpu: 7, memory: 0),
        AppUsage(id: "d", pid: 4, name: "Mail", cpu: 2.2, memory: 0),
        AppUsage(id: "e", pid: 5, name: "Finder", cpu: 0.2, memory: 0),
    ]

    private let sample = BatterySample(
        charge: 0.62, isCharging: false, isOnAC: false, minutesRemaining: 265,
        health: 0.91, cycleCount: 312, temperature: 31, adapterWatts: nil
    )

    @Test(arguments: [true, false])
    func panelOnBattery(dark: Bool) {
        snapshotPanel(
            BatteryPanelContent(battery: sample, apps: apps).frame(width: 320),
            name: "battery-apps", dark: dark
        )
    }

    @Test(arguments: [true, false])
    func panelWithoutApps(dark: Bool) {
        snapshotPanel(
            BatteryPanelContent(battery: sample, apps: []).frame(width: 320),
            name: "battery-quiet", dark: dark
        )
    }
}
