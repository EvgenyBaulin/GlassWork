import AppKit
@testable import GlassWorkUI
import SwiftUI
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct SettingsToastSnapshotTests {
    private var toast: SettingsToast {
        SettingsToast(message: "Undone: Weather", actionTitle: "Redo")
    }

    @Test func toastDark() {
        snapshotPanel(SettingsToastView(toast) {}.padding(20), name: "toast")
    }

    @Test func toastLight() {
        snapshotPanel(SettingsToastView(toast) {}.padding(20), name: "toast", dark: false)
    }
}
