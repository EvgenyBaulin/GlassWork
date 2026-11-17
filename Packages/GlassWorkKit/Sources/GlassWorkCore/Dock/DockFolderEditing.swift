import Foundation

/// The colours a folder's icon can take.
public enum FolderTint: String, Codable, CaseIterable, Sendable {
    case blue, green, orange, red, purple, pink, teal, gray
}

/// The symbols offered for a folder's icon.
public enum FolderSymbols {
    public static let offered = [
        "folder.fill", "briefcase.fill", "gamecontroller.fill", "hammer.fill",
        "paintbrush.fill", "music.note", "book.fill", "star.fill",
    ]
}

/// What travels with an app tile dragged inside the Dock: its path, and the folder it comes from, if any.
public enum DockDrag {
    private static let marker = "folder:"

    public static func payload(path: String, fromFolder folder: UUID? = nil) -> String {
        guard let folder else { return path }
        return "\(marker)\(folder.uuidString):\(path)"
    }

    public static func parse(_ payload: String) -> (path: String, folder: UUID?) {
        guard payload.hasPrefix(marker) else { return (payload, nil) }
        let rest = payload.dropFirst(marker.count)
        guard let colon = rest.firstIndex(of: ":"), let id = UUID(uuidString: String(rest[..<colon])) else {
            return (payload, nil)
        }
        return (String(rest[rest.index(after: colon)...]), id)
    }
}

public extension DockLayout {
    /// Moves an element into another's place, or to the end without one: dragged up it lands in front of it,
    /// dragged down, behind it. Unknown elements change nothing.
    static func moving<Element: Equatable>(
        _ element: Element,
        onto target: Element?,
        in list: [Element]
    ) -> [Element] {
        guard let from = list.firstIndex(of: element), element != target else { return list }
        var result = list
        result.remove(at: from)
        if let target {
            guard let slot = list.firstIndex(of: target) else { return list }
            result.insert(element, at: slot)
        } else {
            result.append(element)
        }
        return result
    }

    /// Moves an element one place, for the buttons beside a list. Stays put at either end.
    static func moving<Element: Equatable>(_ element: Element, by step: Int, in list: [Element]) -> [Element] {
        guard let index = list.firstIndex(of: element) else { return list }
        let destination = index + step
        guard list.indices.contains(destination) else { return list }
        var result = list
        result.swapAt(index, destination)
        return result
    }

    /// Reorders the apps of a folder by hand: the order on show becomes the stored one first, so sorting by name
    /// or use gives way to Manual.
    static func reorder(
        _ app: DockApp,
        onto target: DockApp?,
        inFolder id: UUID,
        in items: [DockItem]
    ) -> [DockItem] {
        items.map { item in
            guard case var .folder(folder) = item, folder.id == id, folder.apps.contains(app) else { return item }
            folder.apps = moving(app, onto: target, in: folder.sortedApps)
            folder.sort = .manual
            return .folder(folder)
        }
    }

    /// Takes an app out of a folder to the top level: in front of an item, or after the folder without one.
    /// A folder left with one app dissolves.
    static func moveOut(
        _ app: DockApp,
        ofFolder id: UUID,
        before target: DockItem? = nil,
        in items: [DockItem]
    ) -> [DockItem] {
        let folder = items.compactMap { item -> AppFolder? in
            if case let .folder(folder) = item, folder.id == id {
                return folder
            }
            return nil
        }.first
        guard let folder, folder.apps.contains(app), !items.contains(.app(app)) else { return items }
        var result = remove(app, from: folder, in: items)
        guard let target, target != .app(app), let from = result.firstIndex(of: .app(app)) else { return result }
        result.remove(at: from)
        result.insert(.app(app), at: result.firstIndex(of: target) ?? from)
        return result
    }

    /// Sets a folder's icon. An emoji wins over a symbol, and both over the grid of apps.
    static func setIcon(
        folder id: UUID,
        symbol: String?,
        emoji: String?,
        tint: FolderTint?,
        in items: [DockItem]
    ) -> [DockItem] {
        items.map { item in
            guard case var .folder(folder) = item, folder.id == id else { return item }
            folder.symbol = symbol
            folder.emoji = emoji.flatMap { $0.isEmpty ? nil : String($0.prefix(1)) }
            folder.tint = tint
            return .folder(folder)
        }
    }
}
