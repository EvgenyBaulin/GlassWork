import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
private final class WaitingInstaller: FanHelperInstalling {
    var state = FanHelperState.needsApproval
    func install() throws {}
    func uninstall() async throws {}
    func openApproval() {}
    func connect(onLost _: @escaping @Sendable () -> Void) -> FanHelperClient? {
        nil
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct SensorGroupsSnapshotTests {
    private func snapshot(_ view: some View, width: CGFloat, height: CGFloat, name: String, scheme: ColorScheme) {
        let background = scheme == .dark ? Color(white: 0.12) : Color(white: 0.95)
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).background(background))
        host.frame = CGRect(x: 0, y: 0, width: width, height: height)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: host, as: .image(precision: 0.98), named: name)
        }
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func groupChoice(scheme: ColorScheme) {
        var stored: [String: String] = [:]
        SensorGroupOptions.set(.gpu, isShown: false, in: &stored)
        SensorGroupOptions.set(.other, isShown: false, in: &stored)
        let view = Form {
            SensorGroupsList(options: SensorGroupOptions(options: stored)) { _, _ in }
        }
        .formStyle(.grouped)
        snapshot(view, width: 460, height: 420, name: "groups-\(scheme)", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func waitingForApprovalOffersCancel(scheme: ColorScheme) {
        let file = SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkSensorGroups-\(UUID().uuidString)/settings.json"))
        let control = FanControlModel(
            store: SettingsStore(file: file),
            installer: WaitingInstaller(),
            readSensors: { nil },
            isOnAC: { true }
        )
        control.refreshHelperState()
        let view = FansPanelContent(
            control: control,
            fans: [FanReading(id: 0, rpm: 3400, minimum: 1350, maximum: 5349)],
            averageCPU: 62,
            curveCelsius: 62,
            points: { _ in [] }
        )
        snapshot(view, width: 340, height: 620, name: "approval-cancel-\(scheme)", scheme: scheme)
    }
}
