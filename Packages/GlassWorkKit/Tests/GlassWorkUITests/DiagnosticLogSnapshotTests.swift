import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DiagnosticLogSnapshotTests {
    private func view(isOn: Bool) -> some View {
        Form {
            DiagnosticLogSection(
                isOn: .constant(isOn),
                path: "~/Library/Logs/GlassWork/diagnostic.log",
                size: 184_000,
                reveal: {},
                send: {}
            )
        }
        .formStyle(.grouped)
        .frame(width: 620, height: isOn ? 240 : 130)
    }

    @Test(arguments: [true, false])
    func off(dark: Bool) {
        snapshotPanel(view(isOn: false), name: "off", dark: dark)
    }

    @Test(arguments: [true, false])
    func on(dark: Bool) {
        snapshotPanel(view(isOn: true), name: "on", dark: dark)
    }
}
