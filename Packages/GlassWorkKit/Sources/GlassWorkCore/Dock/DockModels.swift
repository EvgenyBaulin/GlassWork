import Foundation

public enum DockPosition: String, Codable, CaseIterable, Sendable {
    case bottom, left, right

    public var isVertical: Bool {
        self != .bottom
    }
}

public enum FolderSort: String, Codable, CaseIterable, Sendable {
    case manual, name, mostUsed
}

/// An app kept in the Dock, stored by its path on disk.
public struct DockApp: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String {
        path
    }

    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

/// A folder of apps. Nested folders are not supported.
public struct AppFolder: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var apps: [DockApp]
    public var symbol: String?
    /// An emoji shown in place of the symbol and the grid of apps.
    public var emoji: String?
    /// Colours the symbol and the tile behind it.
    public var tint: FolderTint?
    public var sort = FolderSort.manual
    /// Brought by a preset, and goes when another preset comes.
    public var isFromPreset = false
    /// How many times each app was opened from this folder, by path. Feeds Most Used sorting.
    public var launchCounts: [String: Int] = [:]

    public init(name: String, apps: [DockApp]) {
        self.name = name
        self.apps = apps
    }

    public var sortedApps: [DockApp] {
        switch sort {
        case .manual:
            return apps
        case .name:
            return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .mostUsed:
            // Apps never opened keep the stored order, so a folder without counts looks as it does by hand.
            let counts = launchCounts
            return apps.enumerated().sorted { lhs, rhs in
                let (left, right) = (counts[lhs.element.path] ?? 0, counts[rhs.element.path] ?? 0)
                return left != right ? left > right : lhs.offset < rhs.offset
            }.map(\.element)
        }
    }
}

extension AppFolder {
    private enum CodingKeys: String, CodingKey {
        case id, name, apps, symbol, emoji, tint, sort, isFromPreset, launchCounts
    }

    /// Missing keys fall back to defaults, so a file from an earlier version keeps loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decodeIfPresent(String.self, forKey: .name) ?? "",
            apps: container.decodeIfPresent([DockApp].self, forKey: .apps) ?? []
        )
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        // A colour this version does not know leaves the folder uncoloured instead of losing it.
        tint = try? container.decode(FolderTint.self, forKey: .tint)
        sort = try container.decodeIfPresent(FolderSort.self, forKey: .sort) ?? .manual
        isFromPreset = try container.decodeIfPresent(Bool.self, forKey: .isFromPreset) ?? false
        launchCounts = try container.decodeIfPresent([String: Int].self, forKey: .launchCounts) ?? [:]
    }
}

public enum DockItem: Codable, Sendable, Equatable, Identifiable {
    case app(DockApp)
    case folder(AppFolder)
    case widget(ModuleID)
    case stack(DockStack)

    public var id: String {
        switch self {
        case let .app(app): "app-\(app.path)"
        case let .folder(folder): "folder-\(folder.id)"
        case let .widget(module): "widget-\(module.rawValue)"
        case let .stack(stack): "stack-\(stack.id)"
        }
    }
}

/// What right-clicking an app in the Dock can do.
public enum DockAppCommand: Sendable, Equatable {
    case open, showAllWindows, hide, hideOthers, showInFinder, quit, forceQuit

    /// `hideOthers` and `forceQuit` take the place of the item before them while ⌥ is down.
    public static func offered(isRunning: Bool, canQuit: Bool) -> [DockAppCommand] {
        guard isRunning else { return [.open, .showInFinder] }
        let base: [DockAppCommand] = [.showAllWindows, .hide, .hideOthers, .showInFinder]
        return canQuit ? base + [.quit, .forceQuit] : base
    }
}

public struct DockSettings: Codable, Sendable, Equatable {
    /// Off until the owner turns it on: enabling hides the system Dock.
    public var isEnabled = false
    public var position = DockPosition.bottom
    public var iconSize = 48.0
    public var magnifies = false
    public var magnifiedSize = 80.0
    public var autoHides = false
    public var showsRecents = false
    /// The Trash at the end of the Dock, after the stacks, as in the system Dock.
    public var showsTrash = true
    /// The dot under an app that is running.
    public var showsRunningIndicators = true
    public var items: [DockItem] = []
    /// Turning the Dock on hides the system one, so this is explained once before it happens.
    public var hasSeenIntro = false
    /// The preset in use, by id.
    public var activePreset: String?
    /// Built-ins the owner has changed, and presets of the owner's own.
    public var presets: [DockPreset] = []
    /// Switch presets by the rules below.
    public var followsSchedule = false
    public var schedule: [DockPresetRule] = []

    public init() {}

    /// Every app in the Dock, folders included.
    public var apps: [DockApp] {
        items.flatMap { item -> [DockApp] in
            switch item {
            case let .app(app): [app]
            case let .folder(folder): folder.apps
            case .widget, .stack: []
            }
        }
    }
}

extension DockSettings {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, position, iconSize, magnifies, magnifiedSize, autoHides, showsRecents, showsTrash, items
        case showsRunningIndicators
        case hasSeenIntro, activePreset, presets, followsSchedule, schedule
    }

    /// An item this version cannot read is skipped, so the rest of the Dock survives it.
    private struct LossyItem: Decodable {
        let value: DockItem?

        init(from decoder: Decoder) {
            value = try? DockItem(from: decoder)
        }
    }

    /// Missing keys fall back to defaults: a file written before a setting existed must keep loading.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? isEnabled
        position = try container.decodeIfPresent(DockPosition.self, forKey: .position) ?? position
        iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? iconSize
        magnifies = try container.decodeIfPresent(Bool.self, forKey: .magnifies) ?? magnifies
        magnifiedSize = try container.decodeIfPresent(Double.self, forKey: .magnifiedSize) ?? magnifiedSize
        autoHides = try container.decodeIfPresent(Bool.self, forKey: .autoHides) ?? autoHides
        showsRecents = try container.decodeIfPresent(Bool.self, forKey: .showsRecents) ?? showsRecents
        showsTrash = try container.decodeIfPresent(Bool.self, forKey: .showsTrash) ?? showsTrash
        showsRunningIndicators = try container.decodeIfPresent(Bool.self, forKey: .showsRunningIndicators)
            ?? showsRunningIndicators
        items = try container.decodeIfPresent([LossyItem].self, forKey: .items)?.compactMap(\.value) ?? items
        hasSeenIntro = try container.decodeIfPresent(Bool.self, forKey: .hasSeenIntro) ?? hasSeenIntro
        activePreset = try container.decodeIfPresent(String.self, forKey: .activePreset)
        presets = try container.decodeIfPresent([DockPreset].self, forKey: .presets) ?? presets
        followsSchedule = try container.decodeIfPresent(Bool.self, forKey: .followsSchedule) ?? followsSchedule
        schedule = (try? container.decodeIfPresent([DockPresetRule].self, forKey: .schedule)) ?? schedule
    }
}

public extension DockSettings {
    /// Turns the Dock on. A Dock with nothing in it starts from the system's apps, which are read only then.
    mutating func enable(importing systemApps: () -> [DockApp]) {
        if items.isEmpty {
            items = systemApps().map(DockItem.app)
        }
        hasSeenIntro = true
        isEnabled = true
    }
}

/// Edits the Dock's contents. Pure, so every folder rule is testable.
public enum DockLayout {
    /// Dropping an app on another makes a folder in the target's place. The caller names it, so it can open
    /// the new folder's card by its id.
    public static func drop(
        _ dragged: DockApp,
        onto target: DockApp,
        in items: [DockItem],
        making folder: AppFolder? = nil
    ) -> [DockItem] {
        guard dragged != target, let index = index(of: target, in: items) else { return items }
        var made = folder ?? AppFolder(name: "Folder", apps: [])
        made.apps = [target, dragged]
        var result = items
        result[index] = .folder(made)
        return result.filter { $0 != .app(dragged) }
    }

    /// Dropping an app on a folder adds it, without duplicates.
    public static func drop(_ dragged: DockApp, into folder: AppFolder, in items: [DockItem]) -> [DockItem] {
        var result = items.filter { $0 != .app(dragged) }
        guard let index = result.firstIndex(of: .folder(folder)), !folder.apps.contains(dragged) else { return items }
        var updated = folder
        updated.apps.append(dragged)
        result[index] = .folder(updated)
        return result
    }

    /// Takes an app out of a folder and places it after it. A folder left with one app dissolves.
    public static func remove(_ app: DockApp, from folder: AppFolder, in items: [DockItem]) -> [DockItem] {
        guard let index = items.firstIndex(of: .folder(folder)) else { return items }
        var result = items
        var updated = folder
        updated.apps.removeAll { $0 == app }
        if updated.apps.count <= 1 {
            result.replaceSubrange(index ... index, with: ([app] + updated.apps).map(DockItem.app))
        } else {
            result[index] = .folder(updated)
            result.insert(.app(app), at: index + 1)
        }
        return result
    }

    /// Puts a folder's apps back in the Dock in its place.
    public static func ungroup(_ folder: AppFolder, in items: [DockItem]) -> [DockItem] {
        guard let index = items.firstIndex(of: .folder(folder)) else { return items }
        var result = items
        result.replaceSubrange(index ... index, with: folder.sortedApps.map(DockItem.app))
        return result
    }

    /// Counts an app opened from a folder, for Most Used sorting.
    public static func recordLaunch(_ app: DockApp, inFolder id: UUID, in items: [DockItem]) -> [DockItem] {
        items.map { item in
            guard case var .folder(folder) = item, folder.id == id else { return item }
            folder.launchCounts[app.path, default: 0] += 1
            return .folder(folder)
        }
    }

    /// Renames a folder, found by its id.
    public static func rename(folder id: UUID, to name: String, in items: [DockItem]) -> [DockItem] {
        items.map { item in
            guard case var .folder(folder) = item, folder.id == id else { return item }
            folder.name = name
            return .folder(folder)
        }
    }

    /// Changes how a folder orders its apps, found by its id.
    public static func sort(folder id: UUID, by sort: FolderSort, in items: [DockItem]) -> [DockItem] {
        items.map { item in
            guard case var .folder(folder) = item, folder.id == id else { return item }
            folder.sort = sort
            return .folder(folder)
        }
    }

    private static func index(of app: DockApp, in items: [DockItem]) -> Int? {
        items.firstIndex(of: .app(app))
    }
}

/// Reads the apps pinned to the system Dock. Only reads, so first run can copy them.
public enum SystemDockApps {
    public static func parse(_ persistentApps: [[String: Any]]) -> [DockApp] {
        persistentApps.compactMap { entry in
            guard let tile = entry["tile-data"] as? [String: Any],
                  let file = tile["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String,
                  let url = URL(string: raw)
            else { return nil }
            let name = tile["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
            return DockApp(path: url.path(percentEncoded: false), name: name)
        }
    }

    public static func read() -> [DockApp] {
        let value = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString)
        return parse(value as? [[String: Any]] ?? [])
    }
}

/// The apps opened lately that are not pinned, for the Dock's recents section.
public enum DockRecents {
    /// The Dock shows this many.
    public static let shown = 3
    /// How many are remembered, so that pinning one still leaves others to show.
    public static let remembered = 12

    /// Puts an app first, once.
    public static func record(_ app: DockApp, in history: [DockApp]) -> [DockApp] {
        let key = DockRunningApps.normalized(app.path)
        let rest = history.filter { DockRunningApps.normalized($0.path) != key }
        return Array(([app] + rest).prefix(remembered))
    }

    /// Newest first, without apps already in the Dock.
    public static func visible(_ history: [DockApp], pinned: [DockApp], limit: Int = shown) -> [DockApp] {
        let pinnedKeys = Set(pinned.map { DockRunningApps.normalized($0.path) })
        return Array(history.filter { !pinnedKeys.contains(DockRunningApps.normalized($0.path)) }.prefix(limit))
    }
}
