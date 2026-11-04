import GlassWorkCore
import SwiftUI

public extension SensorChoice {
    var title: String {
        switch self {
        case .averageCPU: loc("avg CPU")
        case .hottestCPU: loc("max CPU core")
        case .averageGPU: loc("avg GPU")
        case .averageSoC: loc("avg SoC")
        case let .sensor(key): key
        }
    }

    /// The word in front of the figure in the menu bar.
    var menuPrefix: String {
        switch self {
        case .averageCPU: loc("avg")
        case .hottestCPU: loc("max")
        case .averageGPU: loc("GPU avg")
        case .averageSoC: loc("SoC avg")
        case let .sensor(key): key
        }
    }
}

/// Settings › Fans: helper and safety on one tab, the curve editor on the other.
public struct FansSettingsPane: View {
    private enum Tab {
        case control, curves
    }

    private let control: FanControlModel
    private let sample: SensorSample?
    private let isOnAC: Bool
    @State private var tab: Tab

    public init(control: FanControlModel, sample: SensorSample?, isOnAC: Bool, showsCurves: Bool = false) {
        self.control = control
        self.sample = sample
        self.isOnAC = isOnAC
        _tab = State(initialValue: showsCurves ? .curves : .control)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(loc("Control")).tag(Tab.control)
                Text(loc("Curves")).tag(Tab.curves)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.top, 14)
            switch tab {
            case .control: FanControlForm(control: control)
            case .curves: FanCurvesForm(control: control, sample: sample, isOnAC: isOnAC)
            }
        }
        .onAppear { control.refreshHelperState() }
    }
}

/// Helper status, the launch mode and what is always guaranteed.
struct FanControlForm: View {
    let control: FanControlModel
    @State private var confirmsUninstall = false

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { control.canControl },
            set: { value in
                if value, control.helperState != .installed {
                    control.install()
                } else {
                    control.setControlEnabled(value)
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: isEnabled) {
                    Text(loc("Enable fan control"))
                    Text(loc("Installs GlassWorkFanHelper once · admin password"))
                }
                LabeledContent(loc("Helper status")) { statusChip }
                if control.helperState == .needsApproval {
                    Button(loc("Open Login Items")) { control.openApproval() }
                }
                Picker(loc("Default mode on launch"), selection: launchMode) {
                    ForEach(FanMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!control.canControl)
            }
            Section(loc("Safety (always on)")) {
                FanSafetyRow("checkmark.shield", loc("Returns to Auto on quit, sleep, restart or crash."))
                FanSafetyRow("timer", loc("The helper returns to Auto if the app is silent for 10 s."))
                FanSafetyRow("thermometer.high", loc("Average CPU above 95 °C switches Curve and Custom to Max."))
                FanSafetyRow("arrow.left.and.right", loc("Speeds are clamped to each fan's SMC minimum and maximum."))
            }
            if control.helperState == .installed {
                Section {
                    Button(loc("Uninstall helper…")) { confirmsUninstall = true }
                } footer: {
                    Text(loc("Removes the LaunchDaemon; fans go back to Auto."))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(loc("Uninstall the fan helper?"), isPresented: $confirmsUninstall) {
            Button(loc("Uninstall"), role: .destructive) {
                Task { await control.uninstall() }
            }
            Button(loc("Cancel"), role: .cancel) {}
        }
    }

    private var launchMode: Binding<FanMode> {
        Binding(
            get: { control.settings.launchMode },
            set: { value in control.updateSettings { $0.launchMode = value } }
        )
    }

    private var statusChip: some View {
        let (text, color): (String, Color) = switch control.helperState {
        case .installed: (loc("Installed"), Palette.green)
        case .needsApproval: (loc("Waiting for approval"), Palette.orange)
        case .installing: (loc("Installing…"), Palette.gray)
        case .notInstalled: (loc("Not installed"), Palette.gray)
        case .failed: (loc("Failed"), Palette.red)
        }
        return Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

struct FanSafetyRow: View {
    private let symbol: String
    private let text: String

    init(_ symbol: String, _ text: String) {
        self.symbol = symbol
        self.text = text
    }

    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 12))
    }
}

/// Settings › Sensors: which value the menu bar item shows.
public struct SensorsMenuBarSection: View {
    private let selection: Binding<SensorChoice>
    private let sample: SensorSample?

    public init(selection: Binding<SensorChoice>, sample: SensorSample?) {
        self.selection = selection
        self.sample = sample
    }

    private static let averages: [SensorChoice] = [.averageCPU, .averageGPU, .averageSoC]

    private var isSingleSensor: Bool {
        if case .sensor = selection.wrappedValue {
            return true
        }
        return false
    }

    public var body: some View {
        Section(loc("Show in menu bar")) {
            Picker(loc("Value"), selection: kind) {
                ForEach(Self.averages, id: \.self) { Text($0.title).tag($0.rawValue) }
                Text(loc("One sensor")).tag(Self.sensorTag)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if isSingleSensor {
                Picker(loc("Sensor"), selection: selection) {
                    ForEach(sensorKeys, id: \.self) { Text($0).tag(SensorChoice.sensor($0)) }
                }
            }
        }
    }

    private static let sensorTag = "sensor"

    private var sensorKeys: [String] {
        let known = sample?.readings.map(\.key) ?? []
        if case let .sensor(key) = selection.wrappedValue, !known.contains(key) {
            return [key] + known
        }
        return known
    }

    private var kind: Binding<String> {
        Binding(
            get: { isSingleSensor ? Self.sensorTag : selection.wrappedValue.rawValue },
            set: { tag in
                if tag == Self.sensorTag {
                    if let key = sample?.readings.first?.key {
                        selection.wrappedValue = .sensor(key)
                    }
                } else if let choice = SensorChoice(rawValue: tag) {
                    selection.wrappedValue = choice
                }
            }
        )
    }
}

/// Settings › Fans module: what the menu bar item shows.
public struct FansMenuBarSection: View {
    private let showsEachFan: Binding<Bool>

    public init(showsEachFan: Binding<Bool>) {
        self.showsEachFan = showsEachFan
    }

    public var body: some View {
        Section(loc("Menu bar shows")) {
            Picker(loc("Value"), selection: showsEachFan) {
                Text(loc("Average")).tag(false)
                Text(loc("Each fan")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
