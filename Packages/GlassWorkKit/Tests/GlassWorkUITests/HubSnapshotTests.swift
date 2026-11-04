import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct HubSnapshotTests {
    /// A store of its own, so the test never sees or changes the real settings file.
    private func store() -> SettingsStore {
        let folder = FileManager.default.temporaryDirectory.appending(path: "GlassWorkHub-\(UUID().uuidString)")
        let store = SettingsStore(file: SettingsFile(url: folder.appending(path: "settings.json")))
        // Only tiles that read the same on any day and any Mac: no fans, uptime, dates or clocks.
        store.update { settings in
            for index in settings.modules.indices {
                let id = settings.modules[index].id
                if id == .fans || id == .uptime || id.group == .everyday || id.group == .extra {
                    settings.modules[index].mode = .off
                }
            }
        }
        return store
    }

    @Test(arguments: [true, false])
    func editMode(dark: Bool) {
        snapshotPanel(HubView(monitor: SystemMonitor(), store: store(), isEditing: true), name: "edit", dark: dark)
    }

    @Test(arguments: [true, false])
    func addingModules(dark: Bool) {
        let view = HubView(monitor: SystemMonitor(), store: store(), isEditing: true, isAddingModules: true)
        snapshotPanel(view, name: "adding", dark: dark)
    }

    /// The rows on their own: a `List` draws nothing offscreen, so dragging itself is checked by hand.
    @Test(arguments: [true, false])
    func orderRows(dark: Bool) {
        let store = store()
        store.update { $0.update(.memory) { $0.mode = .off } }
        let rows = store.settings.modules.prefix(4)
        let view = VStack(spacing: 6) {
            ForEach(rows) { ModuleOrderRow(setting: $0, store: store) }
        }
        .padding(12)
        .frame(width: 560)
        snapshotPanel(view, name: "rows", dark: dark)
    }
}
