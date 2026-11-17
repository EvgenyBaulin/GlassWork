import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockFirstRunSnapshotTests {
    private let presets = [
        DockPreset(id: DockPresetID.everyday.rawValue, name: "Everyday", widgets: [.cpu]),
        DockPreset(id: DockPresetID.developer.rawValue, name: "Developer", widgets: [.cpu]),
        DockPreset(id: DockPresetID.systemMonitor.rawValue, name: "System monitor", widgets: [.cpu]),
    ]

    @Test(arguments: [true, false])
    func waitingForAccessibility(dark: Bool) {
        let view = DockFirstRunView(isTrusted: { false }, startingAt: .accessibility, proceed: {}, cancel: {})
        snapshotPanel(view, name: "first-run-accessibility", dark: dark)
    }

    @Test(arguments: [true, false])
    func accessibilityGranted(dark: Bool) {
        let view = DockFirstRunView(isTrusted: { true }, startingAt: .accessibility, proceed: {}, cancel: {})
        snapshotPanel(view, name: "first-run-granted", dark: dark)
    }

    @Test(arguments: [true, false])
    func choosingAPreset(dark: Bool) {
        let view = DockFirstRunView(presets: presets, isTrusted: { true }, startingAt: .preset, proceed: {}, cancel: {})
        snapshotPanel(view, name: "first-run-preset", dark: dark)
    }
}
