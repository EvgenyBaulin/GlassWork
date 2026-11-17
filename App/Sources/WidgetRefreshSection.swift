import GlassWorkCore
import GlassWorkUI
import SwiftUI
import WidgetKit

/// The note about system widgets, how often they refresh, and the button that refreshes them now.
struct WidgetRefreshSection: View {
    let store: SettingsStore

    /// A saved value outside the list stays selectable.
    private var choices: [Int] {
        let saved = store.settings.widgets.refreshSeconds
        return WidgetSettings.refreshChoices.contains(saved)
            ? WidgetSettings.refreshChoices
            : (WidgetSettings.refreshChoices + [saved]).sorted()
    }

    var body: some View {
        Section {
            Text(loc("Right-click the desktop and choose Edit Widgets to add system widgets."))
                .foregroundStyle(.secondary)
            Picker(loc("Refresh widgets every"), selection: Binding(
                get: { store.settings.widgets.refreshSeconds },
                set: { value in store.update { $0.widgets.refreshSeconds = value } }
            )) {
                ForEach(choices, id: \.self) { Text(Self.title(seconds: $0)).tag($0) }
            }
            Button(loc("Reload All Widgets")) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } header: {
            Text(loc("System widgets"))
        }
    }

    static func title(seconds: Int) -> String {
        seconds < 3600 ? loc("\(seconds / 60) min") : loc("1 hour")
    }
}
