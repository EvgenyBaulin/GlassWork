import Foundation

/// The ready-made Docks.
public enum DockPresetID: String, Codable, CaseIterable, Sendable {
    case everyday, developer, productivity, student, systemMonitor
}

/// A named set of widgets and folders. Applying one leaves the owner's apps and stacks where they are.
public struct DockPreset: Codable, Sendable, Equatable, Identifiable {
    /// A built-in's raw value, or a UUID for one the owner saved.
    public var id: String
    public var name: String
    public var widgets: [ModuleID]
    public var folders: [AppFolder]

    public init(id: String, name: String, widgets: [ModuleID], folders: [AppFolder] = []) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.folders = folders
    }

    public var isBuiltIn: Bool {
        DockPresetID(rawValue: id) != nil
    }

    /// Whether the two would give the same Dock. A folder's id is made anew each time, so it does not count.
    func hasSameContent(as other: DockPreset) -> Bool {
        func outline(_ preset: DockPreset) -> [[String]] {
            preset.folders.map { [$0.name, $0.symbol ?? ""] + $0.apps.map(\.path) }
        }
        return widgets == other.widgets && outline(self) == outline(other)
    }
}

extension DockPreset {
    private enum CodingKeys: String, CodingKey {
        case id, name, widgets, folders
    }

    /// A widget this version does not know is skipped, so the rest of the preset survives it.
    private struct LossyWidget: Decodable {
        let value: ModuleID?

        init(from decoder: Decoder) {
            value = try? ModuleID(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(String.self, forKey: .id),
            name: container.decodeIfPresent(String.self, forKey: .name) ?? "",
            widgets: container.decodeIfPresent([LossyWidget].self, forKey: .widgets)?.compactMap(\.value) ?? [],
            folders: container.decodeIfPresent([AppFolder].self, forKey: .folders) ?? []
        )
    }
}

/// Builds and applies presets. Pure: what is installed comes in through `exists`, so nothing here looks at the disk.
public enum DockPresets {
    private struct FolderPlan {
        let name: String
        var symbol: String?
        let paths: [String]
    }

    private static let system = "/System/Applications/"
    private static let services = "/System/Library/CoreServices/Applications/"

    private static let utilities = FolderPlan(name: "Utilities", paths: [
        "\(system)Calculator.app",
        "\(services)Archive Utility.app",
        "\(system)Utilities/Activity Monitor.app",
        "\(system)Utilities/Disk Utility.app",
        "\(system)Utilities/Console.app",
        "\(services)Keychain Access.app",
        "\(system)Clock.app",
    ])

    private static let devTools = FolderPlan(name: "Dev Tools", paths: [
        "/Applications/Xcode.app",
        "\(system)Utilities/Terminal.app",
        "/Applications/Visual Studio Code.app",
        "/Applications/iTerm.app",
        "/Applications/Docker.app",
        "/Applications/OrbStack.app",
        "/Applications/Postman.app",
        "/Applications/Sublime Text.app",
        "/Applications/GitHub Desktop.app",
        "/Applications/TablePlus.app",
    ])

    private static let office = FolderPlan(name: "Office", paths: [
        "/Applications/Pages.app",
        "/Applications/Numbers.app",
        "/Applications/Keynote.app",
        "\(system)Preview.app",
    ])

    private static let study = FolderPlan(name: "Study", symbol: "graduationcap.fill", paths: [
        "\(system)Books.app",
        "\(system)Notes.app",
        "\(system)Dictionary.app",
        "\(system)Reminders.app",
        "\(system)Freeform.app",
    ])

    /// Only widgets the app has. The design's other ones join these lists once they exist.
    private static func widgets(of id: DockPresetID) -> [ModuleID] {
        switch id {
        case .everyday: [.worldClocks, .calendar, .nowPlaying, .battery, .notes]
        case .developer: [.devServers, .git, .docker, .aiUsage]
        case .productivity: [.endsIn, .todos, .timers, .clipboard]
        case .student: [.calendar, .timers, .countdown]
        case .systemMonitor: [.overview, .network, .disk, .battery, .keepAwake]
        }
    }

    private static func plans(of id: DockPresetID) -> [FolderPlan] {
        switch id {
        case .everyday, .systemMonitor: [utilities]
        case .developer: [devTools, utilities]
        case .productivity: [office]
        case .student: [study]
        }
    }

    /// - Parameter exists: Whether an app is installed. A folder that would hold fewer than two is left out.
    /// - Parameter title: Translates a folder's name.
    public static func builtIn(
        _ id: DockPresetID,
        exists: (String) -> Bool,
        title: (String) -> String = { $0 }
    ) -> DockPreset {
        let folders = plans(of: id).compactMap { plan -> AppFolder? in
            let apps = plan.paths.filter(exists).map { path in
                DockApp(path: path, name: ((path as NSString).lastPathComponent as NSString).deletingPathExtension)
            }
            guard apps.count >= 2 else { return nil }
            var folder = AppFolder(name: title(plan.name), apps: apps)
            folder.symbol = plan.symbol
            return folder
        }
        return DockPreset(id: id.rawValue, name: id.rawValue, widgets: widgets(of: id), folders: folders)
    }

    /// Every preset on offer: the built-ins with the owner's changes, then the owner's own.
    public static func all(
        in dock: DockSettings,
        exists: (String) -> Bool,
        title: (String) -> String = { $0 }
    ) -> [DockPreset] {
        let builtIns = DockPresetID.allCases.map { id in
            dock.presets.first { $0.id == id.rawValue } ?? builtIn(id, exists: exists, title: title)
        }
        return builtIns + dock.presets.filter { !$0.isBuiltIn }
    }

    /// True when the owner has changed a built-in, so it can go back to the original.
    public static func isEdited(_ preset: DockPreset, in dock: DockSettings) -> Bool {
        preset.isBuiltIn && dock.presets.contains { $0.id == preset.id }
    }

    /// What the Dock holds now, as a preset.
    public static func capture(_ dock: DockSettings, id: String, name: String) -> DockPreset {
        let folders = dock.items.compactMap { item -> AppFolder? in
            if case let .folder(folder) = item {
                return folder
            }
            return nil
        }
        return DockPreset(id: id, name: name, widgets: dock.widgets, folders: folders)
    }

    /// Stores a preset, replacing the one with its id.
    public static func store(_ preset: DockPreset, in dock: inout DockSettings) {
        if let index = dock.presets.firstIndex(where: { $0.id == preset.id }) {
            dock.presets[index] = preset
        } else {
            dock.presets.append(preset)
        }
    }

    /// Takes a built-in back to the original, or deletes one of the owner's.
    public static func remove(_ preset: DockPreset, from dock: inout DockSettings) {
        dock.presets.removeAll { $0.id == preset.id }
        if !preset.isBuiltIn, dock.activePreset == preset.id {
            dock.activePreset = nil
        }
    }

    /// Switches the Dock to a preset. Changes made to the one in use are kept with it.
    ///
    /// Replaces widgets and the folders a preset brought. Apps, the owner's own folders and stacks stay: a preset
    /// must not cost anyone their Dock, and a stack is never added, because reading a folder can raise a prompt.
    ///
    /// - Parameter current: The preset in use, as it was applied.
    public static func apply(_ preset: DockPreset, current: DockPreset?, to dock: inout DockSettings) {
        if let current, current.id != preset.id {
            var edited = capture(dock, id: current.id, name: current.name)
            // The owner's own folders are no part of a preset, and having one is not a change to it.
            edited.folders = edited.folders.filter(\.isFromPreset)
            if !edited.hasSameContent(as: current) {
                store(edited, in: &dock)
            }
        }
        let names = Set(preset.folders.map(\.name))
        let kept = dock.items.filter { item in
            switch item {
            case .app, .stack: true
            case .widget: false
            case let .folder(folder): !folder.isFromPreset && !names.contains(folder.name)
            }
        }
        let folders = preset.folders.map { folder -> DockItem in
            var fresh = folder
            fresh.id = UUID()
            fresh.isFromPreset = true
            return .folder(fresh)
        }
        dock.items = kept + folders + preset.widgets.map(DockItem.widget)
        dock.activePreset = preset.id
    }
}

public extension DockLayout {
    /// Puts a folder in an app's place.
    static func replacing(_ app: DockApp, with folder: AppFolder, in items: [DockItem]) -> [DockItem] {
        items.map { $0 == .app(app) ? .folder(folder) : $0 }
    }

    /// Adds an empty folder, ready for apps to be dragged in.
    static func addingFolder(_ folder: AppFolder, to items: [DockItem]) -> [DockItem] {
        items + [.folder(folder)]
    }

    /// An empty folder has no reason to stay once its card closes.
    ///
    /// - Parameter open: The card open now, by item id. A folder just made is empty until apps are dragged in.
    static func removingEmptyFolders(from items: [DockItem], keeping open: String? = nil) -> [DockItem] {
        items.filter { item in
            if case let .folder(folder) = item {
                return !folder.apps.isEmpty || item.id == open
            }
            return true
        }
    }
}

public extension DockSettings {
    /// Every folder in the Dock, in order.
    var folders: [AppFolder] {
        items.compactMap { item in
            if case let .folder(folder) = item {
                return folder
            }
            return nil
        }
    }
}
