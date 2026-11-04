import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Reports whichever helper state a test asks for. It connects to nothing.
@MainActor
private final class StubInstaller: FanHelperInstalling {
    var state: FanHelperState

    init(state: FanHelperState) {
        self.state = state
    }

    func install() throws {}
    func uninstall() async throws {}
    func openApproval() {}
    func connect(onLost _: @escaping @Sendable () -> Void) -> FanHelperClient? {
        nil
    }
}

private final class StubClient: FanHelperClient {
    func send(_: FanCommand) async -> Bool {
        true
    }

    func heartbeat() async -> Bool {
        true
    }

    func disconnect() {}
}

@MainActor
private final class ConnectedInstaller: FanHelperInstalling {
    let state = FanHelperState.installed
    func install() throws {}
    func uninstall() async throws {}
    func openApproval() {}
    func connect(onLost _: @escaping @Sendable () -> Void) -> FanHelperClient? {
        StubClient()
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct FanSnapshotTests {
    private let fans = [
        FanReading(id: 0, rpm: 3400, minimum: 1350, maximum: 5349),
        FanReading(id: 1, rpm: 3380, minimum: 1458, maximum: 5777),
    ]

    private var sample: SensorSample {
        SensorSample(
            readings: [
                SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 62),
                SensorReading(key: "Tg01", group: .gpu, celsius: 48),
            ],
            fans: fans
        )
    }

    private func history(_ fan: Int) -> [History<Double>.Point] {
        var history = History<Double>(capacity: 30)
        for index in 0 ..< 30 {
            let wave = sin(Double(index + fan) / 4) * 120
            history.append(3400 + wave, at: Date(timeIntervalSince1970: 1_800_000_000 + Double(index) * 2))
        }
        return history.points
    }

    private func store(_ change: (inout AppSettings) -> Void = { _ in }) -> SettingsStore {
        let file = SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkFanSnapshots-\(UUID().uuidString)/settings.json"))
        let store = SettingsStore(file: file)
        store.update(change)
        return store
    }

    private func model(
        _ state: FanHelperState,
        enabled: Bool = true,
        change: (inout AppSettings) -> Void = { _ in }
    ) -> FanControlModel {
        FanControlModel(
            store: store {
                $0.fans.isControlEnabled = enabled
                change(&$0)
            },
            installer: StubInstaller(state: state),
            readSensors: { nil },
            isOnAC: { true }
        )
    }

    /// A model in `mode`, reached through the same calls the panel makes.
    private func running(_ mode: FanMode, celsius: Double = 62) async -> FanControlModel {
        let reading = SensorSample(
            readings: [SensorReading(key: "Tp01", group: .cpuPerformance, celsius: celsius)],
            fans: fans
        )
        let model = FanControlModel(
            store: store { $0.fans.isControlEnabled = true },
            installer: ConnectedInstaller(),
            readSensors: { reading },
            isOnAC: { true }
        )
        model.select(mode)
        await model.step()
        return model
    }

    private func panel(_ control: FanControlModel, curveHover: Double? = nil, cpu: Double = 62) -> some View {
        FansPanelContent(
            control: control,
            fans: fans,
            averageCPU: cpu,
            curveCelsius: cpu,
            points: { history($0) },
            curveHover: curveHover
        )
    }

    private func snapshot(
        _ view: some View,
        width: CGFloat,
        height: CGFloat,
        name: String,
        scheme: ColorScheme = .dark
    ) {
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
    func panelWithoutTheHelper(scheme: ColorScheme) {
        snapshot(
            panel(model(.notInstalled, enabled: false)),
            width: 340,
            height: 640,
            name: "helper-off-\(scheme)",
            scheme: scheme
        )
    }

    @Test func panelWaitingForApproval() {
        snapshot(panel(model(.needsApproval, enabled: false)), width: 340, height: 620, name: "approval")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func panelInAuto(scheme: ColorScheme) {
        snapshot(panel(model(.installed)), width: 340, height: 480, name: "auto-\(scheme)", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func handOverControl(scheme: ColorScheme) {
        let control = model(.installed) {
            $0.fans.handsOverWhenCool = true
            $0.fans.handOverCelsius = 45
        }
        snapshot(
            Form { FanHandOverSection(control: control) }.formStyle(.grouped),
            width: 460,
            height: 190,
            name: "hand-over-\(scheme)",
            scheme: scheme
        )
    }

    @Test func panelInCurveMode() async {
        await snapshot(panel(running(.curve)), width: 340, height: 640, name: "curve")
    }

    @Test func panelHoveringTheCurve() async {
        await snapshot(panel(running(.curve), curveHover: 75), width: 340, height: 640, name: "curve-hover")
    }

    @Test func panelInCustomMode() async {
        await snapshot(panel(running(.custom)), width: 340, height: 600, name: "custom")
    }

    @Test func panelInMax() async {
        await snapshot(panel(running(.max)), width: 340, height: 480, name: "max")
    }

    @Test func panelAfterTheFailsafe() async {
        let control = await running(.custom, celsius: 96)
        snapshot(panel(control, cpu: 96), width: 340, height: 620, name: "failsafe")
    }

    @Test func panelOnAMacWithoutFans() {
        let view = FansPanelContent(
            control: model(.notInstalled),
            fans: [],
            averageCPU: nil,
            curveCelsius: nil,
            points: { _ in [] }
        )
        snapshot(view, width: 340, height: 200, name: "no-fans")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func curveChart(scheme: ColorScheme) {
        let chart = FanCurveChart(
            curve: FanPreset.balanced.curve,
            rpmRange: 1350 ... 5349,
            live: .init(celsius: 62, rpm: 3400),
            showsAxes: true,
            height: 240
        )
        snapshot(chart.padding(8), width: 560, height: 256, name: "chart-\(scheme)", scheme: scheme)
    }

    @Test func curveChartHover() {
        let chart = FanCurveChart(
            curve: FanPreset.balanced.curve,
            rpmRange: 1350 ... 5349,
            live: .init(celsius: 62, rpm: 3400),
            showsAxes: true,
            height: 240,
            hover: 70
        )
        snapshot(chart.padding(8), width: 560, height: 256, name: "chart-hover")
    }

    @Test func curveChartWithTheOtherFan() {
        let chart = FanCurveChart(
            curve: FanPreset.balanced.curve,
            otherCurve: FanPreset.silent.curve,
            rpmRange: 1350 ... 5349,
            showsAxes: true,
            height: 240
        )
        snapshot(chart.padding(8), width: 560, height: 256, name: "chart-two-curves")
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func controlTab(scheme: ColorScheme) {
        snapshot(
            FansSettingsPane(control: model(.installed), sample: sample, isOnAC: true),
            width: 640,
            height: 520,
            name: "settings-control-\(scheme)",
            scheme: scheme
        )
    }

    @Test func controlTabWithoutTheHelper() {
        snapshot(
            FansSettingsPane(control: model(.notInstalled, enabled: false), sample: sample, isOnAC: true),
            width: 640,
            height: 480,
            name: "settings-control-off"
        )
    }

    @Test(arguments: [ColorScheme.dark, .light])
    func curvesTab(scheme: ColorScheme) {
        snapshot(
            FansSettingsPane(control: model(.installed), sample: sample, isOnAC: true, showsCurves: true),
            width: 640,
            height: 1120,
            name: "settings-curves-\(scheme)",
            scheme: scheme
        )
    }

    @Test func curvesTabLockedWithoutTheHelper() {
        snapshot(
            FansSettingsPane(
                control: model(.notInstalled, enabled: false),
                sample: sample,
                isOnAC: true,
                showsCurves: true
            ),
            width: 640,
            height: 1120,
            name: "settings-curves-locked"
        )
    }

    @Test func sensorsMenuBarSection() {
        let view = Form {
            SensorsMenuBarSection(selection: .constant(.sensor("Tp01")), sample: sample)
            FansMenuBarSection(showsEachFan: .constant(true))
        }
        .formStyle(.grouped)
        snapshot(view, width: 520, height: 260, name: "menu-bar-sections")
    }
}
