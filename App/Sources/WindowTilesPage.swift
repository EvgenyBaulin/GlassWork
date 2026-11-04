import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Connects the pane to settings and to the system. The pane itself knows neither, so moving it to another
/// window means moving this one line of `detail` with it.
struct WindowTilesPage: View {
    let store: SettingsStore
    let shortcuts: ShortcutCenter
    @State private var isTrusted = Accessibility.isTrusted

    var body: some View {
        WindowTilesPane(
            isEnabled: binding(\.isEnabled),
            showsPreview: binding(\.showsPreview),
            isTrusted: isTrusted,
            takenShortcuts: taken,
            shortcuts: store.settings.shortcuts,
            openAccessibilitySettings: Accessibility.openSettings
        )
        .task {
            // macOS does not announce the change, and this page is where people wait for it.
            while !Task.isCancelled {
                isTrusted = Accessibility.isTrusted
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Shortcuts another app got to first, which therefore do nothing here.
    private var taken: [String] {
        TileCommand.all.compactMap { command in
            let action = ShortcutAction.tile(command)
            return shortcuts.refused.contains(action) ? store.settings.shortcuts.shortcut(for: action)?.label : nil
        }
    }

    private func binding(_ keyPath: WritableKeyPath<WindowTilesSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.settings.windowTiles[keyPath: keyPath] },
            set: { value in store.update { $0.windowTiles[keyPath: keyPath] = value } }
        )
    }
}
