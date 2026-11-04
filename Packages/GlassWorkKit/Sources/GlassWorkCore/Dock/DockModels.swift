import Foundation

public enum DockPosition: String, Codable, CaseIterable, Sendable {
    case bottom, left, right
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
    public var sort = FolderSort.manual

    public init(name: String, apps: [DockApp]) {
        self.name = name
        self.apps = apps
    }

    public var sortedApps: [DockApp] {
        sort == .name
            ? apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : apps
    }
}

public enum DockItem: Codable, Sendable, Equatable, Identifiable {
    case app(DockApp)
    case folder(AppFolder)
    case widget(ModuleID)

    public var id: String {
        switch self {
        case let .app(app): "app-\(app.path)"
        case let .folder(folder): "folder-\(folder.id)"
        case let .widget(module): "widget-\(module.rawValue)"
        }
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
    public var items: [DockItem] = []

    public init() {}

    /// Every app in the Dock, folders included.
    public var apps: [DockApp] {
        items.flatMap { item -> [DockApp] in
            switch item {
            case let .app(app): [app]
            case let .folder(folder): folder.apps
            case .widget: []
            }
        }
    }
}

/// Edits the Dock's contents. Pure, so every folder rule is testable.
public enum DockLayout {
    /// Dropping an app on another makes a folder in the target's place.
    public static func drop(_ dragged: DockApp, onto target: DockApp, in items: [DockItem]) -> [DockItem] {
        guard dragged != target, let index = index(of: target, in: items) else { return items }
        var result = items
        result[index] = .folder(AppFolder(name: "Folder", apps: [target, dragged]))
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
