import GlassWorkCore
import SwiftUI

/// The sections a module's table entries add to its Settings page. Rare options fold away under Advanced.
public struct ModuleOptionRows: View {
    private let module: ModuleID
    private let store: SettingsStore
    @State private var showsAdvanced: Bool
    @Environment(\.settingsHighlight) private var highlight

    public init(module: ModuleID, store: SettingsStore) {
        self.init(module: module, store: store, showsAdvanced: false)
    }

    init(module: ModuleID, store: SettingsStore, showsAdvanced: Bool) {
        self.module = module
        self.store = store
        _showsAdvanced = State(initialValue: showsAdvanced)
    }

    public var body: some View {
        let rows = ModuleOptionSpec.rows(for: module)
        let main = rows.filter { !$0.isAdvanced }
        let advanced = rows.filter(\.isAdvanced)
        if !main.isEmpty {
            Section(loc("Options")) {
                ForEach(main) { OptionRow(spec: $0, store: store) }
            }
        }
        if !advanced.isEmpty {
            Section {
                DisclosureGroup(isExpanded: advancedIsOpen(advanced)) {
                    ForEach(advanced) { OptionRow(spec: $0, store: store) }
                } label: {
                    HStack(spacing: 8) {
                        Text(loc("Advanced")).font(.system(size: 13, weight: .semibold))
                        Text(loc("\(advanced.count) rarely needed options"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private extension ModuleOptionRows {
    /// A search result inside Advanced has to be seen, so it opens the section.
    func advancedIsOpen(_ rows: [ModuleOptionSpec]) -> Binding<Bool> {
        Binding(
            get: { showsAdvanced || rows.contains { $0.id == highlight } },
            set: { showsAdvanced = $0 }
        )
    }
}

/// The Hub's rows, for the Menu Bar page.
public struct HubOptionRows: View {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public var body: some View {
        Section(loc("Hub")) {
            ForEach(ModuleOptionSpec.hubOptions) { OptionRow(spec: $0, store: store) }
        }
    }
}

/// One table entry as a control. Everything goes through `store.update`, so ⌘Z takes it back.
struct OptionRow: View {
    let spec: ModuleOptionSpec
    let store: SettingsStore
    @Environment(\.settingsHighlight) private var highlight

    private var value: Binding<String> {
        Binding(
            get: { spec.read(store.settings) },
            set: { new in store.update { spec.write(&$0, new) } }
        )
    }

    private var isOn: Binding<Bool> {
        Binding(get: { value.wrappedValue == "true" }, set: { value.wrappedValue = String($0) })
    }

    var body: some View {
        control.listRowBackground(highlight == spec.id ? Palette.yellow.opacity(0.18) : nil)
    }

    @ViewBuilder
    private var control: some View {
        switch spec.kind {
        case .toggle:
            Toggle(spec.localizedTitle, isOn: isOn)
        case let .choice(choices):
            if isSegmented(choices) {
                picker(choices).pickerStyle(.segmented)
            } else {
                picker(choices).pickerStyle(.menu)
            }
        case let .number(range, step, unit):
            LabeledContent(spec.localizedTitle) {
                HStack(spacing: 6) {
                    Text(verbatim: unitText(unit)).monospacedDigit()
                    Stepper("", value: number(range), in: range, step: step).labelsHidden()
                }
            }
        case let .text(placeholder):
            LabeledContent(spec.localizedTitle) {
                TextField("", text: value, prompt: Text(verbatim: placeholder))
                    .font(.system(size: 12, design: .monospaced))
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func picker(_ choices: [OptionChoice]) -> some View {
        Picker(spec.localizedTitle, selection: value) {
            ForEach(choices, id: \.value) { choice in
                Text(loc(String.LocalizationValue(choice.title))).tag(choice.value)
            }
        }
    }

    /// Short lists read best side by side; anything longer would not fit the row.
    private func isSegmented(_ choices: [OptionChoice]) -> Bool {
        choices.count <= 3 && choices.allSatisfy { $0.title.count <= 12 }
    }

    private func number(_ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { min(max(Int(value.wrappedValue) ?? range.lowerBound, range.lowerBound), range.upperBound) },
            set: { value.wrappedValue = String($0) }
        )
    }

    private func unitText(_ unit: String) -> String {
        let shown = unit == "min" || unit == "ms" ? loc(String.LocalizationValue(unit)) : unit
        return shown.isEmpty ? value.wrappedValue : "\(value.wrappedValue) \(shown)"
    }
}
