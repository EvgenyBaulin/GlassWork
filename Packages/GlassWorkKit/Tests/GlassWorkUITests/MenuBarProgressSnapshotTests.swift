import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct MenuBarProgressSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        _ content: ItemContent,
        module: ModuleID,
        style: DisplayStyle,
        name: String,
        dark: Bool
    ) throws {
        let renderer = MenuBarItemRenderer(module: module, style: style, numbers: .compact, monitor: SystemMonitor())
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textWidth = ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
        let size = CGSize(width: 16 + 34 + 4 * 4 + (style == .graphAndFigure ? textWidth : 0), height: 24)
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = try #require(renderer.image(content: content, size: size))
        view.contentTintColor = .labelColor
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }

    @Test(arguments: [true, false])
    func timerGraph(dark: Bool) throws {
        let timer = CountdownTimer(title: "T", duration: 400, start: now.addingTimeInterval(-100))
        let item = ItemContent.timers([timer], at: now, options: [:])
        try snapshot(item, module: .timers, style: .graph, name: "progress-timer-graph", dark: dark)
        try snapshot(item, module: .timers, style: .graphAndFigure, name: "progress-timer-both", dark: dark)
    }

    @Test(arguments: [true, false])
    func batteryGraph(dark: Bool) throws {
        let devices = [DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.6)]
        let item = ItemContent.deviceBatteries(devices, options: [:])
        try snapshot(item, module: .deviceBatteries, style: .graph, name: "progress-battery-graph", dark: dark)
    }

    @Test(arguments: [true, false])
    func emptyAndFullGraph(dark: Bool) throws {
        let free = ItemContent.endsIn([], at: now, options: [:])
        try snapshot(free, module: .endsIn, style: .graph, name: "progress-free-graph", dark: dark)
        var full = ItemContent(figure: "—", template: "—")
        full.glyph = .progress(1)
        try snapshot(full, module: .countdown, style: .graph, name: "progress-full-graph", dark: dark)
    }
}
