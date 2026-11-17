import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct GeneralSettingsSnapshotTests {
    private let rows = [
        PermissionRowModel(permission: .calendars, state: .granted),
        PermissionRowModel(permission: .reminders, state: .notGranted),
        PermissionRowModel(permission: .location, state: .notNeeded),
        PermissionRowModel(permission: .screenRecording, state: .notGranted),
    ]

    @Test(arguments: [true, false])
    func permissions(dark: Bool) {
        let view = PermissionsPaneView(rows: rows) { _ in }.frame(width: 620, height: 360)
        snapshotPanel(view, name: "permissions", dark: dark)
    }

    @Test(arguments: [true, false])
    func regionalChosen(dark: Bool) {
        var settings = RegionalSettings()
        settings.language = .russian
        settings.timeFormat = .twentyFourHour
        let view = Form { RegionalSection(settings: .constant(settings), runningLanguage: .system) }
            .formStyle(.grouped)
            .frame(width: 620, height: 260)
        snapshotPanel(view, name: "regional", dark: dark)
    }

    @Test(arguments: [true, false])
    func updatesOn(dark: Bool) {
        let status = AutoUpdateStatus(
            isInstalled: true,
            lastBuild: Date(timeIntervalSince1970: 1_794_000_000),
            nextCheck: Date(timeIntervalSince1970: 1_794_900_000),
            nextBuild: Date(timeIntervalSince1970: 1_795_000_000)
        )
        let view = Form { AutoUpdateSection(status: status, hasLog: true) {} }
            .formStyle(.grouped)
            .frame(width: 620, height: 260)
        snapshotPanel(view, name: "updatesOn", dark: dark)
    }

    @Test(arguments: [true, false])
    func updatesOff(dark: Bool) {
        let status = AutoUpdateStatus(
            isInstalled: false,
            lastBuild: nil,
            nextCheck: Date(timeIntervalSince1970: 1_794_900_000),
            nextBuild: nil
        )
        let view = Form { AutoUpdateSection(status: status, hasLog: false) {} }
            .formStyle(.grouped)
            .frame(width: 620, height: 240)
        snapshotPanel(view, name: "updatesOff", dark: dark)
    }

    @Test(arguments: [true, false])
    func onboardingSets(dark: Bool) {
        let view = OnboardingSetPicker(selected: .constant([.developer, .mac]))
            .padding(24)
            .frame(width: 480, height: 280)
        snapshotPanel(view, name: "sets", dark: dark)
    }

    @Test(arguments: [true, false])
    func onboardingPermissions(dark: Bool) {
        let view = OnboardingPermissionsView(rows: Array(rows.prefix(2))) { _ in }
            .padding(24)
            .frame(width: 480, height: 160)
        snapshotPanel(view, name: "onboardingPermissions", dark: dark)
    }

    @Test(arguments: [true, false])
    func onboardingSummary(dark: Bool) {
        let view = OnboardingSummaryView(
            sets: [.developer, .mac],
            launchAtLogin: .constant(true),
            openSettings: {},
            addWidgets: {}
        )
        .padding(24)
        .frame(width: 480, height: 240)
        snapshotPanel(view, name: "summary", dark: dark)
    }
}
