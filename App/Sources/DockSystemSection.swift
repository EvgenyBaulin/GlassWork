import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The system Dock's settings as GlassWork saved them when it took over, and a way to put them back.
struct DockSystemSection: View {
    let store: SettingsStore
    @State private var saved = SystemDock.saved
    @State private var isConfirming = false

    var body: some View {
        Section {
            if let saved {
                LabeledContent(loc("Auto-hide")) { Text(Self.describe(saved.autoHides)) }
                LabeledContent(loc("Auto-hide delay")) {
                    Text(saved.autoHideDelay.map { loc("\($0.formatted()) s") } ?? loc("Not set"))
                }
                Button(loc("Restore System Dock…")) { isConfirming = true }
            } else {
                Text(loc("Nothing saved: GlassWork has not changed the system Dock."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(loc("System Dock"))
        } footer: {
            Text(loc("These are the system Dock's own settings from before GlassWork Dock took over."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { saved = SystemDock.saved }
        .onChange(of: store.settings.dock.isEnabled) { _, _ in saved = SystemDock.saved }
        .alert(loc("Restore the system Dock?"), isPresented: $isConfirming) {
            Button(loc("Restore")) { restore() }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("GlassWork Dock turns off and the system Dock comes back with the settings shown here."))
        }
    }

    private static func describe(_ value: Bool?) -> String {
        switch value {
        case true: loc("On")
        case false: loc("Off")
        case nil: loc("Not set")
        }
    }

    private func restore() {
        if store.settings.dock.isEnabled {
            // Turning the Dock off closes it, and closing restores the system one.
            store.update { $0.dock.isEnabled = false }
        } else {
            SystemDock.restore()
        }
        saved = SystemDock.saved
        // Closing the Dock restores a moment later.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            saved = SystemDock.saved
        }
    }
}
