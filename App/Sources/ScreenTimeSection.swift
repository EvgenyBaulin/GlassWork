import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Whether the front app is tracked, when a day starts, which apps are left out, and deleting what was kept.
struct ScreenTimeSection: View {
    let store: SettingsStore
    let activity: ActivityStore
    @State private var isConfirmingReset = false

    private var dayStart: Int {
        store.settings.widgets.dayStartHour
    }

    private var excluded: [String] {
        activity.screenTime.excluded.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        Section(loc("Screen Time")) {
            Toggle(loc("Track which app is in front"), isOn: Binding(
                get: { store.settings.widgets.tracksScreenTime },
                set: { value in store.update { $0.widgets.tracksScreenTime = value } }
            ))
            Picker(loc("Day starts at"), selection: Binding(
                get: { dayStart },
                set: { value in store.update { $0.widgets.dayStartHour = value } }
            )) {
                ForEach(0 ... 6, id: \.self) { Text(Self.title(hour: $0)).tag($0) }
            }
            excludedApps
            Text(loc("Stored only on this Mac for 30 days."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(loc("Reset Data…"), role: .destructive) { isConfirmingReset = true }
        }
        .alert(loc("Reset Screen Time data?"), isPresented: $isConfirmingReset) {
            Button(loc("Reset"), role: .destructive) { activity.resetScreenTime() }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("Everything kept for Screen Time is deleted from this Mac. This cannot be undone."))
        }
    }

    @ViewBuilder
    private var excludedApps: some View {
        LabeledContent(loc("Apps not counted")) {
            Menu(loc("Add App")) {
                ForEach(Self.runningAppNames(except: activity.screenTime.excluded), id: \.self) { name in
                    Button(name) { setExcluded(activity.screenTime.excluded.union([name])) }
                }
            }
            .fixedSize()
        }
        ForEach(excluded, id: \.self) { name in
            HStack {
                Text(name)
                Spacer()
                Button(loc("Remove"), role: .destructive) {
                    setExcluded(activity.screenTime.excluded.subtracting([name]))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func setExcluded(_ names: Set<String>) {
        activity.configureScreenTime(dayStartHour: dayStart, excluded: names)
    }

    /// Names as the front-app tracking records them.
    private static func runningAppNames(except excluded: Set<String>) -> [String] {
        let names = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
            .filter { !excluded.contains($0) }
        return Set(names).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func title(hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
