import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Dock settings: switch presets by time and day.
struct DockScheduleSection: View {
    let store: SettingsStore

    private var dock: DockSettings {
        store.settings.dock
    }

    var body: some View {
        Section {
            Toggle(loc("Switch presets on a schedule"), isOn: Binding(
                get: { dock.followsSchedule },
                set: { value in store.update { $0.dock.followsSchedule = value } }
            ))
            if dock.followsSchedule {
                ForEach(dock.schedule) { rule in
                    DockRuleRow(rule: rule, presets: DockPresets.offered(in: dock)) { change in
                        store.update { settings in
                            guard let index = settings.dock.schedule.firstIndex(where: { $0.id == rule.id }) else {
                                return
                            }
                            if let change {
                                settings.dock.schedule[index] = change
                            } else {
                                settings.dock.schedule.remove(at: index)
                            }
                        }
                    }
                }
                Button(loc("Add Rule")) {
                    let preset = dock.activePreset ?? DockPresetID.everyday.rawValue
                    store.update { $0.dock.schedule.append(DockPresetRule(presetID: preset, minute: 9 * 60)) }
                }
            }
        } header: {
            Text(loc("Schedule"))
        } footer: {
            Text(
                loc(
                    "Rules switch the Dock at their time and days. A preset picked by hand stays until the next rule."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// One rule: which preset, from what time, on which days. A nil change deletes it.
private struct DockRuleRow: View {
    let rule: DockPresetRule
    let presets: [DockPreset]
    let change: (DockPresetRule?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker(loc("Preset"), selection: Binding(
                    get: { rule.presetID },
                    set: { value in edit { $0.presetID = value } }
                )) {
                    Text(loc("No Preset")).tag(String?.none)
                    ForEach(presets) { Text($0.title).tag(String?.some($0.id)) }
                }
                .labelsHidden()
                .fixedSize()
                DatePicker(loc("From"), selection: Binding(
                    get: { time },
                    set: { value in edit { $0.minute = Self.minute(of: value) } }
                ), displayedComponents: .hourAndMinute)
                    .environment(\.locale, RegionalFormat.locale)
                Spacer()
                Button(role: .destructive) { change(nil) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help(loc("Delete"))
            }
            HStack(spacing: 4) {
                ForEach(Self.weekOrder, id: \.self) { day in
                    let isOn = rule.weekdays.contains(day)
                    Button(Self.symbol(of: day)) {
                        edit { rule in
                            if isOn {
                                rule.weekdays.remove(day)
                            } else {
                                rule.weekdays.insert(day)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(isOn ? Palette.blue : nil)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func edit(_ body: (inout DockPresetRule) -> Void) {
        var copy = rule
        body(&copy)
        change(copy)
    }

    private var time: Date {
        Calendar.current
            .date(byAdding: .minute, value: rule.minute, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private static func minute(of date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The week as the owner's calendar starts it.
    private static var weekOrder: [Int] {
        let first = RegionalFormat.calendar.firstWeekday
        return (0 ..< 7).map { (first - 1 + $0) % 7 + 1 }
    }

    private static func symbol(of weekday: Int) -> String {
        Calendar.current.veryShortStandaloneWeekdaySymbols[weekday - 1]
    }
}
