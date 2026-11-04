import GlassWorkCore
import SwiftUI

/// Presets, sensor, the editor, its table and the power rules.
struct FanCurvesForm: View {
    let control: FanControlModel
    let sample: SensorSample?
    let isOnAC: Bool
    @State private var selection: Int?
    @State private var editingFan = 0
    @State private var naming: Naming?
    @State private var newName = ""
    @State private var confirmsDelete = false

    private enum Naming {
        case saveAs, rename
    }

    private var settings: FanSettings {
        control.settings
    }

    private var fans: [FanReading] {
        sample?.fans.filter(\.hasValidRange) ?? []
    }

    private var rpmRange: ClosedRange<Double> {
        let fan = fans.first { $0.id == editingFan } ?? fans.first
        return fan.map { $0.minimum ... $0.maximum } ?? 1200 ... 5800
    }

    private var otherCurve: FanCurve? {
        guard settings.separateCurves else { return nil }
        return fans.first { $0.id != editingFan }.map { settings.curve(forFan: $0.id, isOnAC: isOnAC) }
    }

    private var live: FanCurveChart.Live? {
        guard let celsius = sample?.celsius(for: settings.sensor) else { return nil }
        let rpm = fans.first { $0.id == editingFan }?.rpm ?? 0
        return FanCurveChart.Live(celsius: celsius, rpm: rpm)
    }

    var body: some View {
        Form {
            Section { header }
            Section(loc("Presets")) { presets }
            Section { editor }
            Section(loc("Points")) {
                FanPointsTable(
                    curve: settings.selectedCurve,
                    range: rpmRange,
                    isEnabled: control.canControl,
                    selection: $selection
                ) {
                    apply($0)
                }
            }
            Section {
                Label(loc("Hysteresis 3 °C · 5 s rolling average · at most 300 rpm/s"), systemImage: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } header: {
                Text(loc("Smoothing"))
            }
            FanHandOverSection(control: control)
            FanPowerRulesSection(control: control, isOnAC: isOnAC)
        }
        .formStyle(.grouped)
        .disabled(!control.canControl)
        .alert(naming == .rename ? loc("Rename curve") : loc("Save curve as"), isPresented: isNaming) {
            TextField(loc("Name"), text: $newName)
            Button(loc("Save")) { commitName() }
            Button(loc("Cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            loc("Delete “\(settings.selectedPreset.title)”?"),
            isPresented: $confirmsDelete
        ) {
            Button(loc("Delete"), role: .destructive) {
                control.updateSettings { $0.deletePreset($0.selectedPresetID) }
            }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("Anything that uses this curve switches to Balanced."))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(loc("Curve sensor"), selection: sensor) {
                ForEach(
                    [SensorChoice.averageCPU, .hottestCPU, .averageGPU, .averageSoC],
                    id: \.self
                ) { choice in
                    Text(choice.title).tag(choice)
                }
                if let sample {
                    Divider()
                    ForEach(sample.readings) { reading in
                        Text(reading.key).tag(SensorChoice.sensor(reading.key))
                    }
                }
            }
            Toggle(loc("Separate curve per fan"), isOn: separateCurves)
            if settings.separateCurves, fans.count > 1 {
                Picker(loc("Editing fan"), selection: fanToEdit) {
                    ForEach(fans) { Text($0.title(among: fans.count)).tag($0.id) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(loc("Curve"), selection: preset) {
                ForEach(settings.presets) { Text($0.title).tag($0.id) }
            }
            if settings.hasDraft {
                Text(loc("\(settings.curveTitle) · unsaved")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button(loc("Save as…")) { askForName(.saveAs) }
                Button(loc("Duplicate")) {
                    let name = loc("\(settings.selectedPreset.title) copy")
                    control.updateSettings { $0.saveCurve(as: name) }
                }
                if settings.hasDraft {
                    Button(loc("Revert")) { control.updateSettings { $0.draftPoints = [] } }
                }
                if !settings.selectedPreset.isBuiltIn {
                    Button(loc("Rename…")) { askForName(.rename) }
                    Button(loc("Delete…"), role: .destructive) { confirmsDelete = true }
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                FanCurveChart(
                    curve: settings.selectedCurve,
                    otherCurve: otherCurve,
                    rpmRange: rpmRange,
                    live: live,
                    isEditable: control.canControl,
                    showsAxes: true,
                    height: 240,
                    selection: $selection
                ) { apply($0) }
                if !control.canControl {
                    Label(loc("Enable fan control to edit curves"), systemImage: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(8)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                }
            }
            Text(loc("Drag a point · double-click to add · select and press ⌫ to delete · 2–8 points"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ curve: FanCurve) {
        control.updateSettings { $0.applyEdit(curve) }
    }

    private var isNaming: Binding<Bool> {
        Binding(get: { naming != nil }, set: {
            if !$0 {
                naming = nil
            }
        })
    }

    private func askForName(_ purpose: Naming) {
        newName = settings.selectedPreset.title
        naming = purpose
    }

    private func commitName() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if naming == .rename {
            control.updateSettings { $0.renamePreset($0.selectedPresetID, to: name) }
        } else {
            control.updateSettings { $0.saveCurve(as: name) }
        }
    }

    private var sensor: Binding<SensorChoice> {
        Binding(get: { settings.sensor }, set: { value in control.updateSettings { $0.sensor = value } })
    }

    private var preset: Binding<String> {
        Binding(
            get: { settings.selectedPresetID },
            set: { id in
                control.updateSettings { fans in
                    fans.selectPreset(id)
                    if fans.separateCurves, fans.fanPresetIDs.indices.contains(editingFan) {
                        fans.fanPresetIDs[editingFan] = id
                    }
                }
                selection = nil
            }
        )
    }

    private var separateCurves: Binding<Bool> {
        Binding(
            get: { settings.separateCurves },
            set: { value in
                let count = fans.count
                control.updateSettings { settings in
                    settings.separateCurves = value
                    if value, settings.fanPresetIDs.count < count {
                        settings.fanPresetIDs = Array(repeating: settings.selectedPresetID, count: count)
                    }
                }
            }
        )
    }

    private var fanToEdit: Binding<Int> {
        Binding(
            get: { editingFan },
            set: { fan in
                editingFan = fan
                control.updateSettings { settings in
                    if settings.fanPresetIDs.indices.contains(fan) {
                        settings.selectPreset(settings.fanPresetIDs[fan])
                    }
                }
            }
        )
    }
}

/// Exact values for every point. Typed numbers are held inside the neighbours, like a drag.
struct FanPointsTable: View {
    let curve: FanCurve
    let range: ClosedRange<Double>
    let isEnabled: Bool
    @Binding var selection: Int?
    let onChange: (FanCurve) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text(loc("Temp °C")).foregroundStyle(.secondary)
                    ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
                        field(point.celsius, index: index, isTemperature: true)
                    }
                }
                GridRow {
                    Text(loc("Speed %")).foregroundStyle(.secondary)
                    ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
                        field(point.percent, index: index, isTemperature: false)
                    }
                }
                GridRow {
                    Text(loc("≈ rpm")).foregroundStyle(.secondary)
                    ForEach(Array(curve.points.enumerated()), id: \.offset) { _, point in
                        Text(Format.rpm(FanCurve.rpm(percent: point.percent, in: range)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .font(.system(size: 11))
            HStack {
                Button(loc("Add point"), systemImage: "plus") { addPoint() }
                    .disabled(curve.points.count >= FanCurve.pointLimit.upperBound)
                Button(loc("Remove point"), systemImage: "minus") { removePoint() }
                    .disabled(selection == nil || curve.points.count <= FanCurve.pointLimit.lowerBound)
            }
            .labelStyle(.iconOnly)
        }
    }

    private func field(_ value: Double, index: Int, isTemperature: Bool) -> some View {
        let binding = Binding(
            get: { value },
            set: { typed in
                if isTemperature {
                    moved(index, celsius: typed)
                } else {
                    moved(index, percent: typed)
                }
            }
        )
        return TextField("", value: binding, format: .number.precision(.fractionLength(0)))
            .textFieldStyle(.roundedBorder)
            // Without this a Form lays the field out as a labelled row and breaks the columns.
            .labelsHidden()
            .frame(width: 44)
            .multilineTextAlignment(.center)
            .disabled(!isEnabled)
    }

    private func moved(_ index: Int, celsius: Double? = nil, percent: Double? = nil) {
        let point = curve.points[index]
        selection = index
        onChange(curve.moving(index, to: .init(
            celsius: celsius ?? point.celsius,
            percent: percent ?? point.percent
        )))
    }

    /// Splits the widest gap, the one place a new point is most useful.
    private func addPoint() {
        let pairs = zip(curve.points, curve.points.dropFirst())
        guard let widest = pairs.max(by: { $0.1.celsius - $0.0.celsius < $1.1.celsius - $1.0.celsius }) else { return }
        let celsius = ((widest.0.celsius + widest.1.celsius) / 2).rounded()
        if let added = curve.inserting(.init(celsius: celsius, percent: curve.percent(at: celsius).rounded())) {
            onChange(added)
        }
    }

    private func removePoint() {
        guard let selection, let removed = curve.removing(selection) else { return }
        self.selection = nil
        onChange(removed)
    }
}

/// Below a set temperature the fans are left to macOS, which can stop them, instead of holding the minimum.
struct FanHandOverSection: View {
    let control: FanControlModel

    private var settings: FanSettings {
        control.settings
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.handsOverWhenCool },
            set: { value in control.updateSettings { $0.handsOverWhenCool = value } }
        )
    }

    private var celsius: Binding<Double> {
        Binding(
            get: { settings.handOverCelsius },
            set: { value in control.updateSettings { $0.handOverCelsius = value } }
        )
    }

    var body: some View {
        Section {
            Toggle(loc("Let macOS run the fans when the Mac is cool"), isOn: isOn)
            if settings.handsOverWhenCool {
                Stepper(value: celsius, in: FanSettings.handOverRange, step: 1) {
                    LabeledContent(loc("Below"), value: Format.temperature(settings.handOverCelsius))
                }
                Text(loc("The curve takes over again \(Format.temperature(FanHandOver.band)) above this."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(loc("When cool"))
        }
    }
}

struct FanPowerRulesSection: View {
    let control: FanControlModel
    let isOnAC: Bool

    private var rules: FanPowerRules {
        control.settings.powerRules
    }

    var body: some View {
        Section {
            Toggle(loc("Use a different curve on battery"), isOn: Binding(
                get: { rules.isEnabled },
                set: { value in control.updateSettings { $0.powerRules.isEnabled = value } }
            ))
            picker(loc("On power adapter"), Binding(
                get: { rules.adapterPresetID },
                set: { id in control.updateSettings { $0.powerRules.adapterPresetID = id } }
            ))
            picker(loc("On battery"), Binding(
                get: { rules.batteryPresetID },
                set: { id in control.updateSettings { $0.powerRules.batteryPresetID = id } }
            ))
        } header: {
            Text(loc("Power rules"))
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        guard rules.isEnabled else { return loc("Off: the selected curve is used on any power source.") }
        let id = isOnAC ? rules.adapterPresetID : rules.batteryPresetID
        let title = control.settings.preset(id).title
        return isOnAC ? loc("Now on power adapter → \(title)") : loc("Now on battery → \(title)")
    }

    private func picker(_ title: String, _ selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(control.settings.presets) { Text($0.title).tag($0.id) }
        }
        .disabled(!rules.isEnabled)
    }
}
