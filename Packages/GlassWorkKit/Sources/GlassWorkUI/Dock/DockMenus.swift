import GlassWorkCore
import SwiftUI

public extension DockPreset {
    /// The name to show. A built-in's is translated, and the owner's stays as typed.
    var title: String {
        switch DockPresetID(rawValue: id) {
        case .everyday: loc("Preset everyday")
        case .developer: loc("Preset developer")
        case .productivity: loc("Preset productivity")
        case .student: loc("Preset student")
        case .systemMonitor: loc("Preset system monitor")
        case nil: name
        }
    }
}

public extension DockPresets {
    /// Every preset on offer, on this Mac and in this language.
    static func offered(in dock: DockSettings) -> [DockPreset] {
        all(in: dock, exists: { FileManager.default.fileExists(atPath: $0) }, title: folderTitle)
    }

    /// The key is built first: written inside the value it would become "Folder %@", which is not in the catalog.
    internal static func folderTitle(_ name: String) -> String {
        let key = "Folder \(name)"
        return String(localized: String.LocalizationValue(key), bundle: .module)
    }
}

/// Right-click on an app. Holding ⌥ swaps Hide and Quit for their stronger forms, as in the system Dock.
struct DockAppMenu: View {
    let app: DockApp
    let actions: DockActions
    /// The Dock's folders. Nil inside a folder's card, where the app is not on the bar and has no Options.
    var folders: [AppFolder]?
    /// Opens a card by item id, for a folder that has just been made.
    var openCard: (String) -> Void = { _ in }

    var body: some View {
        let commands = actions.commands(app)
        if commands.contains(.open) {
            button(loc("Open"), .open)
        }
        if let folders {
            options(folders)
            Divider()
        }
        if commands.contains(.showAllWindows) {
            button(loc("Show All Windows"), .showAllWindows)
        }
        if commands.contains(.hide) {
            button(loc("Hide"), .hide).modifierKeyAlternate(.option) {
                button(loc("Hide Others"), .hideOthers)
            }
            Divider()
        }
        if folders == nil {
            button(loc("Show in Finder"), .showInFinder)
        }
        if commands.contains(.quit) {
            Divider()
            button(loc("Quit"), .quit).modifierKeyAlternate(.option) {
                button(loc("Force Quit"), .forceQuit)
            }
        }
    }

    private func button(_ title: String, _ command: DockAppCommand) -> some View {
        Button(title) { actions.perform(command, app) }
    }

    /// Everything here stays in the Dock's own settings. Open at Login is left out: another app's login item can
    /// only be set by writing to the system or by scripting System Events, which raises a prompt.
    private func options(_ folders: [AppFolder]) -> some View {
        Menu(loc("Options")) {
            Toggle(loc("Keep in Dock"), isOn: Binding(get: { true }, set: { _ in remove() }))
            button(loc("Show in Finder"), .showInFinder)
            Divider()
            Menu(loc("Add to Folder")) {
                ForEach(folders) { folder in
                    Button(folder.name) { actions.update { DockLayout.drop(app, into: folder, in: $0) } }
                }
                if !folders.isEmpty {
                    Divider()
                }
                Button(loc("New Folder…")) { makeFolder() }
            }
            Divider()
            Button(loc("Remove from Dock")) { remove() }
        }
    }

    private func remove() {
        actions.update { DockLayout.removing(.app(app), from: $0) }
    }

    /// Opens at once, for the name to be typed.
    private func makeFolder() {
        let folder = AppFolder(name: loc("New Folder"), apps: [app])
        actions.update { DockLayout.replacing(app, with: folder, in: $0) }
        openCard(DockItem.folder(folder).id)
    }
}

/// Right-click on empty space in the Dock.
struct DockBackgroundMenu: View {
    let settings: DockSettings
    let actions: DockActions
    /// Opens a card by item id, for a folder that has just been made.
    let openCard: (String) -> Void

    var body: some View {
        Button(settings.magnifies ? loc("Turn Magnification Off") : loc("Turn Magnification On")) {
            actions.change { $0.magnifies.toggle() }
        }
        Button(settings.autoHides ? loc("Turn Hiding Off") : loc("Turn Hiding On")) {
            actions.change { $0.autoHides.toggle() }
        }
        Menu(loc("Position on Screen")) {
            ForEach(DockPosition.allCases, id: \.self) { position in
                Toggle(position.title, isOn: Binding(
                    get: { settings.position == position },
                    set: { _ in actions.change { $0.position = position } }
                ))
            }
        }
        Divider()
        Button(loc("New Folder")) { makeFolder() }
        presets
        Divider()
        Button(loc("Dock Settings…")) { actions.openSettings() }
    }

    private var presets: some View {
        Menu(loc("Presets")) {
            ForEach(actions.presets()) { preset in
                Toggle(preset.title, isOn: Binding(
                    get: { settings.activePreset == preset.id },
                    set: { _ in actions.applyPreset(preset) }
                ))
            }
            Divider()
            Button(loc("Save Current as Preset…")) { actions.savePreset() }
            Button(loc("Edit Presets…")) { actions.openSettings() }
        }
    }

    /// Opens at once, so apps can be dragged in. Left empty, it goes when its card closes, however that happens.
    private func makeFolder() {
        let folder = AppFolder(name: loc("New Folder"), apps: [])
        actions.update { DockLayout.addingFolder(folder, to: $0) }
        openCard(DockItem.folder(folder).id)
    }
}
