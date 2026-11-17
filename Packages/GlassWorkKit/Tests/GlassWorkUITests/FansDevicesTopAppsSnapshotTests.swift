import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The Fans XL curve list, the Top Apps ranking and the device checklist, in both appearances.
/// Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct FansDevicesTopAppsSnapshotTests {
    private func render(_ kind: WidgetKind, _ snapshot: WidgetSnapshot, name: String, sizes: [WidgetSize]) {
        for size in sizes {
            for dark in [true, false] {
                widgetSnapshot(
                    WidgetFace(kind: kind, size: size, snapshot: snapshot, now: sampleNow),
                    size: size,
                    dark: dark,
                    named: "\(name)-\(size.rawValue)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    private func fans(mode: FanMode, selected: String) -> WidgetSnapshot {
        var snapshot = DataSamples.fanSnapshot
        var settings = FanSettings()
        settings.saveCurve(as: "Quiet Studio", id: "quiet")
        settings.saveCurve(as: "Render Night", id: "render")
        snapshot.fans = WidgetFanState(
            mode: mode,
            control: .ready,
            presets: settings.presets.map { WidgetFanState.Preset(id: $0.id, name: $0.name) },
            selectedPresetID: selected,
            customRPM: 3600
        )
        return snapshot
    }

    @Test func fansExtraLargeListsTheSavedCurves() {
        render(.fans, fans(mode: .curve, selected: "quiet"), name: "fans-curves-curve", sizes: [.extraLarge])
        render(.fans, fans(mode: .custom, selected: "balanced"), name: "fans-curves-custom", sizes: [.extraLarge])
    }

    private var apps: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.apps = [
            ProcessUsage(pid: 1, name: "Safari", cpu: 14.2, memory: 2_400_000_000),
            ProcessUsage(pid: 2, name: "Xcode", cpu: 38.5, memory: 5_100_000_000),
            ProcessUsage(pid: 3, name: "Mail", cpu: 1.4, memory: 900_000_000),
            ProcessUsage(pid: 4, name: "Music", cpu: 6.1, memory: 700_000_000),
            ProcessUsage(pid: 5, name: "Slack", cpu: 9.8, memory: 1_300_000_000),
            ProcessUsage(pid: 6, name: "Finder", cpu: 0.6, memory: 400_000_000),
            ProcessUsage(pid: 7, name: "Notes", cpu: 0.2, memory: 350_000_000),
            ProcessUsage(pid: 8, name: "Preview", cpu: 0.1, memory: 300_000_000),
            ProcessUsage(pid: 9, name: "Terminal", cpu: 2.3, memory: 250_000_000),
        ]
        return snapshot
    }

    @Test func topAppsByMemory() {
        var snapshot = apps
        snapshot.topAppsOptions = TopAppsOptions(ranking: .memory)
        render(.topApps, snapshot, name: "top-apps-memory", sizes: [.medium, .large])
    }

    @Test func topAppsByCPUWithAChosenCount() {
        var snapshot = apps
        snapshot.topAppsOptions = TopAppsOptions(ranking: .cpu, count: 3)
        render(.topApps, snapshot, name: "top-apps-cpu-3", sizes: [.medium])
        snapshot.topAppsOptions = TopAppsOptions(ranking: .cpu, count: 8)
        render(.topApps, snapshot, name: "top-apps-cpu-8", sizes: [.large])
    }

    @Test(arguments: [true, false])
    func deviceChecklist(dark: Bool) {
        let selection = DeviceSelection(options: [
            ItemOption.seenDevices: "Magic Mouse\nAirPods Pro\nMagic Keyboard",
            ItemOption.excludedDevices: "Magic Keyboard",
        ])
        let view = Form { DeviceChoices(selection: selection) { _, _ in } }
            .formStyle(.grouped)
            .frame(width: 360, height: 220)
        snapshotPanel(view, name: "devices-checklist", dark: dark)
        let empty = Form { DeviceChoices(selection: DeviceSelection()) { _, _ in } }
            .formStyle(.grouped)
            .frame(width: 360, height: 160)
        snapshotPanel(empty, name: "devices-checklist-empty", dark: dark)
    }
}

@MainActor
struct DeviceFigureTests {
    private let devices = [
        DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.1),
        DeviceBattery(name: "Keyboard", kind: .keyboard, charge: 0.8),
    ]

    @Test func theFigureCountsEveryDeviceByDefault() {
        let item = ItemContent.deviceBatteries(devices, options: [:])
        #expect(item.figure == Format.percent(0.1))
    }

    @Test func anUntickedDeviceDoesNotDragTheFigureDown() {
        let item = ItemContent.deviceBatteries(devices, options: [ItemOption.excludedDevices: "Mouse"])
        #expect(item.figure == Format.percent(0.8))
        #expect(item.glyph == .progress(0.8))
        #expect(item.alert == nil)
    }

    @Test func aDeviceSeenForTheFirstTimeIsIncluded() {
        let more = devices + [DeviceBattery(name: "Pods", kind: .headphones, charge: 0.05)]
        let item = ItemContent.deviceBatteries(more, options: [ItemOption.excludedDevices: "Mouse"])
        #expect(item.figure == Format.percent(0.05))
    }

    @Test func withEveryDeviceUntickedThereIsNothingToShow() {
        let item = ItemContent.deviceBatteries(devices, options: [ItemOption.excludedDevices: "Mouse\nKeyboard"])
        #expect(item.figure == "—")
    }
}
