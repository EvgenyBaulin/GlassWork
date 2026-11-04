import GlassWorkCore
import SwiftUI

public extension EnvironmentValues {
    /// Fan control for the views that need it. Nil in previews of unrelated panels.
    @Entry var fanControl: FanControlModel?
}

public extension FanMode {
    var title: String {
        switch self {
        case .auto: loc("Auto")
        case .curve: loc("Curve")
        case .max: loc("Max")
        case .custom: loc("Custom")
        }
    }
}

public extension FanPreset {
    /// Built-in names are translated; user curves keep what the user typed.
    var title: String {
        switch id {
        case FanPreset.silent.id: loc("Silent")
        case FanPreset.balanced.id: loc("Balanced")
        case FanPreset.performance.id: loc("Performance")
        default: name
        }
    }
}

public extension FanSettings {
    /// "Balanced", or "Balanced (edited)" while an edit is unsaved.
    var curveTitle: String {
        hasDraft ? loc("\(selectedPreset.title) (edited)") : selectedPreset.title
    }
}

extension FanReading {
    func title(among count: Int) -> String {
        guard count == 2 else { return count == 1 ? loc("Fan") : loc("Fan \(id + 1)") }
        return id == 0 ? loc("Left fan") : loc("Right fan")
    }
}

/// Live readings around the fan controls.
struct FansPanel: View {
    let monitor: SystemMonitor
    @State private var range = TieredHistory.Range.minute
    @Environment(\.fanControl) private var control

    var body: some View {
        if let control {
            let sample = monitor.sensors
            FansPanelContent(
                control: control,
                fans: sample?.fans ?? [],
                averageCPU: sample?.averageCPU,
                curveCelsius: sample?.celsius(for: control.settings.sensor),
                points: { monitor.fanPoints($0, in: range) }
            )
            // Approval happens in System Settings, so the state may have changed since last time.
            .onAppear { control.refreshHelperState() }
        }
    }
}

/// The panel itself. It takes plain values, so every state can be tested without hardware.
struct FansPanelContent: View {
    let control: FanControlModel
    let fans: [FanReading]
    let averageCPU: Double?
    let curveCelsius: Double?
    let points: (Int) -> [History<Double>.Point]
    var curveHover: Double?
    @Environment(\.panelActions) private var actions

    private var isMax: Bool {
        control.mode == .max
    }

    private var average: Double? {
        fans.isEmpty ? nil : fans.map(\.rpm).reduce(0, +) / Double(fans.count)
    }

    private var valueColor: Color {
        isMax ? Palette.orange : .primary
    }

    var body: some View {
        PanelFrame(module: .fans, subtitle: control.mode.title) {
            if fans.isEmpty {
                Text(loc("No fans in this Mac"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                figures
                if let notice = control.notice {
                    FanNoticeBanner(notice: notice, control: control)
                }
                if !control.canControl {
                    FanHelperCard(control: control)
                }
                modeRow
                if control.mode == .curve {
                    curveSection
                }
                if control.mode == .custom {
                    FanCustomControls(control: control, fans: fans)
                }
                ForEach(fans) { fan in
                    FanCard(fan: fan, title: fan.title(among: fans.count), isMax: isMax, points: points(fan.id))
                }
                footnote
            }
        }
    }

    private var figures: some View {
        HStack(alignment: .firstTextBaseline) {
            BigFigure(text: average.map(Format.groupedRPM) ?? "—").foregroundStyle(valueColor)
            Text(loc("rpm avg")).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(loc("avg CPU")).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(averageCPU.map(Format.temperature) ?? "—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
        }
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            Picker("", selection: Binding(get: { control.mode }, set: { control.select($0) })) {
                ForEach(FanMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            // Text only: with four modes beside it, an icon pushes the button out of the panel.
            Button {
                control.toggleMax()
            } label: {
                Text(loc("Max")).font(.system(size: 11, weight: .semibold))
            }
            .tint(isMax ? Palette.orange : nil)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()
            .help(loc("Turn Max on or off with one click"))
        }
        .disabled(!control.canControl)
    }

    private var curveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(loc("Curve"), selection: Binding(
                    get: { control.settings.selectedPresetID },
                    set: { id in control.updateSettings { $0.selectPreset(id) } }
                )) {
                    ForEach(control.settings.presets) { Text($0.title).tag($0.id) }
                }
                Spacer()
                Button(loc("Edit curves…")) { actions.openFanCurves() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            .font(.system(size: 12))
            if let fan = fans.first(where: \.hasValidRange) {
                FanCurveChart(
                    curve: control.settings.curve(forFan: fan.id, isOnAC: true),
                    rpmRange: fan.minimum ... fan.maximum,
                    live: curveCelsius.map { FanCurveChart.Live(celsius: $0, rpm: fan.rpm) },
                    height: 96,
                    hover: curveHover
                )
            }
        }
    }

    private var footnote: some View {
        Label(footnoteText, systemImage: control.canControl ? "checkmark.shield" : "lock")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private var footnoteText: String {
        guard control.canControl else { return loc("Readings work without the helper") }
        return control.mode == .curve
            ? loc("Smoothing on · 95 °C → Max")
            : loc("Helper running · Auto on quit, sleep, crash")
    }
}

/// One fan: speed, its SMC range and a history graph.
struct FanCard: View {
    let fan: FanReading
    let title: String
    let isMax: Bool
    let points: [History<Double>.Point]

    private var tint: Color {
        isMax ? Palette.orange : Palette.cyan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "fan").foregroundStyle(tint)
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(loc("\(Format.rpm(fan.rpm)) rpm"))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isMax ? Palette.orange : .primary)
            }
            Text(loc("min \(Format.rpm(fan.minimum)) · max \(Format.rpm(fan.maximum)) rpm"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            InteractiveChart(
                series: [ChartSeries(
                    id: "fan\(fan.id)",
                    title: title,
                    color: tint,
                    points: points,
                    format: { loc("\(Format.rpm($0)) rpm") }
                )],
                domain: 0 ... max(fan.maximum, 1),
                height: 40
            )
        }
        .padding(10)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }
}

/// Explains why control is locked and offers the one way to unlock it.
struct FanHelperCard: View {
    let control: FanControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc("Fan control is off"), systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(explanation)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: .rect(cornerRadius: 10))
    }

    private var explanation: String {
        switch control.helperState {
        case .needsApproval:
            loc("Allow GlassWork in System Settings › General › Login Items, then come back.")
        case let .failed(message):
            loc("The helper could not be installed: \(message)")
        default:
            loc("""
            GlassWork installs a small helper (GlassWorkFanHelper) to change fan speed. \
            macOS asks for an administrator password once. Reading speeds works without it.
            """)
        }
    }

    @ViewBuilder
    private var action: some View {
        switch control.helperState {
        case .needsApproval:
            Button(loc("Open Login Items")) { control.openApproval() }.buttonStyle(.borderedProminent)
        case .installing:
            ProgressView().controlSize(.small)
        case .installed:
            Button(loc("Enable fan control")) { control.setControlEnabled(true) }.buttonStyle(.borderedProminent)
        case .notInstalled, .failed:
            Button(loc("Enable fan control")) { control.install() }.buttonStyle(.borderedProminent)
        }
    }
}

/// Failsafe and fallback messages.
struct FanNoticeBanner: View {
    let notice: FanNotice
    let control: FanControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.orange.opacity(0.4)))
    }

    private var title: String {
        switch notice {
        case let .failsafeMax(celsius, _): loc("CPU \(Format.temperature(celsius)) — switched to Max")
        case .returnedToAuto: loc("Returned to Auto")
        }
    }

    private var message: String {
        switch notice {
        case .failsafeMax: loc("Average CPU went above 95 °C. Max stays on until you pick a mode.")
        case .returnedToAuto(.sleep): loc("Fans went back to the system when the Mac slept.")
        case .returnedToAuto(.helperLost): loc("The connection to the helper was lost.")
        case .returnedToAuto(.sensorLost): loc("The temperature sensor stopped reporting.")
        }
    }

    @ViewBuilder
    private var action: some View {
        if case let .failsafeMax(_, previous) = notice {
            Button(previous == .curve ? loc("Back to Curve") : loc("Back to Custom")) { control.select(previous) }
                .buttonStyle(.bordered)
        } else {
            Button(loc("OK")) { control.dismissNotice() }.buttonStyle(.bordered)
        }
    }
}

/// Target speed for all fans at once, or for each one.
struct FanCustomControls: View {
    let control: FanControlModel
    let fans: [FanReading]

    private var perFan: Binding<Bool> {
        Binding(
            get: { control.settings.customPerFan },
            set: { value in
                control.updateSettings { settings in
                    settings.customPerFan = value
                    if value, settings.customRPMs.count < fans.count {
                        settings.customRPMs = fans.map { settings.customTarget(forFan: $0.id) }
                    }
                }
            }
        )
    }

    private var bounds: ClosedRange<Double> {
        let valid = fans.filter(\.hasValidRange)
        let lower = valid.map(\.minimum).min() ?? 0
        return lower ... max(valid.map(\.maximum).max() ?? 1, lower + 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(loc("Each fan separately"), isOn: perFan).font(.system(size: 12))
            if control.settings.customPerFan {
                ForEach(fans.filter(\.hasValidRange)) { fan in
                    FanTargetSlider(
                        title: fan.title(among: fans.count),
                        value: control.settings.customTarget(forFan: fan.id),
                        range: fan.minimum ... fan.maximum
                    ) { rpm in
                        control.updateSettings { settings in
                            if settings.customRPMs.indices.contains(fan.id) {
                                settings.customRPMs[fan.id] = rpm
                            }
                        }
                    }
                }
            } else {
                FanTargetSlider(title: loc("All fans"), value: control.settings.customRPM, range: bounds) { rpm in
                    control.updateSettings { $0.customRPM = rpm }
                }
            }
        }
    }
}

/// Saves only when the drag ends, so a moving slider does not rewrite settings.json.
struct FanTargetSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let commit: (Double) -> Void
    @State private var draft: Double?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
            Slider(
                value: Binding(
                    get: { draft ?? min(max(value, range.lowerBound), range.upperBound) },
                    set: { draft = $0 }
                ),
                in: range
            ) { isEditing in
                if !isEditing, let draft {
                    commit(draft.rounded())
                    self.draft = nil
                }
            }
            Text(Format.rpm(draft ?? value))
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }
}
