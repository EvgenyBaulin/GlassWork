import Darwin
import Foundation

public enum DockStackStyle: String, Codable, CaseIterable, Sendable {
    case fan, grid
}

/// A folder kept in the Dock, opened above it.
public struct DockStack: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var path: String
    public var name: String
    public var style = DockStackStyle.grid
    /// Shows newest files in a list with search and download progress.
    public var isDownloads = false

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }

    /// Only names the folder: nothing here touches it, which matters because macOS guards it.
    public static func downloads(name: String) -> DockStack {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        var stack = DockStack(path: folder.path(percentEncoded: false), name: name)
        stack.isDownloads = true
        return stack
    }

    /// The system Dock shows a fan only at the bottom: at a side it would run off the screen.
    public func showsFan(at position: DockPosition) -> Bool {
        !isDownloads && style == .fan && position == .bottom
    }
}

extension DockStack {
    private enum CodingKeys: String, CodingKey {
        case id, path, name, style, isDownloads
    }

    /// Missing keys fall back to defaults, so a later field does not cost the stack.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            path: container.decode(String.self, forKey: .path),
            name: container.decodeIfPresent(String.self, forKey: .name) ?? ""
        )
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        style = try container.decodeIfPresent(DockStackStyle.self, forKey: .style) ?? .grid
        isDownloads = try container.decodeIfPresent(Bool.self, forKey: .isDownloads) ?? false
    }
}

/// A file or folder inside a stack.
public struct DockFile: Sendable, Equatable, Identifiable {
    public var id: String {
        path
    }

    public var path: String
    public var name: String
    public var size: Int64
    public var added: Date
    public var isFolder: Bool
    /// Still being written by a browser.
    public var isDownloading: Bool
    /// From 0 to 1, when the browser publishes it.
    public var progress: Double?

    public init(
        path: String,
        name: String,
        size: Int64 = 0,
        added: Date,
        isFolder: Bool = false,
        isDownloading: Bool = false,
        progress: Double? = nil
    ) {
        self.path = path
        self.name = name
        self.size = size
        self.added = added
        self.isFolder = isFolder
        self.isDownloading = isDownloading
        self.progress = progress
    }

    /// The part that tells the file's type. A download in progress is named after what it will become.
    public var typeExtension: String {
        (name as NSString).pathExtension.lowercased()
    }
}

/// Sorting, searching and download state. Pure, so it runs on made-up files and never on a real folder.
public enum DockFiles {
    /// What browsers call a file they are still writing.
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial", "opdownload"]
    /// How many files a fan shows, as in the design.
    public static let fanLimit = 7

    /// Newest first. The name settles ties, so the order never flickers.
    public static func sorted(_ files: [DockFile]) -> [DockFile] {
        files.sorted { first, second in
            first.added != second.added
                ? first.added > second.added
                : first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    public static func matching(_ files: [DockFile], query: String) -> [DockFile] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? files : files.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    public static func isPartial(name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// "report.pdf.crdownload" is shown as "report.pdf".
    public static func displayName(of name: String) -> String {
        isPartial(name: name) ? (name as NSString).deletingPathExtension : name
    }

    /// Reads the progress macOS shows on a file in Finder, stored as text in an extended attribute.
    public static func progress(fromAttribute data: Data?) -> Double? {
        guard let data, let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
        guard let value = Double(trimmed), (0 ... 1).contains(value) else { return nil }
        return value
    }

    /// All downloads as one share, for the tile. Nil when none of them says how far it has come.
    public static func overallProgress(_ files: [DockFile]) -> Double? {
        let known = files.filter(\.isDownloading).compactMap(\.progress)
        return known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
    }
}

/// The arc of a fan: each file further from the Dock leans further to the side.
public enum DockFan {
    /// As drawn in the design, in points.
    private static let curve = 2.2

    /// - Parameter index: 0 is the file nearest the Dock.
    public static func offset(at index: Int) -> Double {
        curve * Double(index * index)
    }
}

/// Reads a folder. This is the only place that does, and the app calls it only for stacks in the Dock: reading
/// Downloads, Documents or Desktop can raise a macOS prompt.
public struct DockFolderReader: Sendable {
    private static let progressAttribute = "com.apple.progress.fractionCompleted"

    public init() {}

    public func read(_ path: String) -> [DockFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .addedToDirectoryDateKey, .creationDateKey, .isDirectoryKey]
        let contents = try? FileManager.default.contentsOfDirectory(
            at: URL(filePath: path),
            includingPropertiesForKeys: keys,
            options: .skipsHiddenFiles
        )
        return DockFiles.sorted((contents ?? []).map { file(at: $0, keys: Set(keys)) })
    }

    private func file(at url: URL, keys: Set<URLResourceKey>) -> DockFile {
        let values = try? url.resourceValues(forKeys: keys)
        let name = url.lastPathComponent
        let isPartial = DockFiles.isPartial(name: name)
        return DockFile(
            path: url.path(percentEncoded: false),
            name: DockFiles.displayName(of: name),
            size: Int64(values?.fileSize ?? 0),
            added: values?.addedToDirectoryDate ?? values?.creationDate ?? .distantPast,
            // Safari's download is a package, and still counts as a file.
            isFolder: values?.isDirectory == true && !isPartial,
            isDownloading: isPartial,
            progress: isPartial ? DockFiles.progress(fromAttribute: attribute(of: url)) : nil
        )
    }

    private func attribute(of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, Self.progressAttribute, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, Self.progressAttribute, &bytes, size, 0, 0)
            return read > 0 ? Data(bytes.prefix(read)) : nil
        }
    }
}

public extension DockSettings {
    /// Every stack in the Dock, in order.
    var stacks: [DockStack] {
        items.compactMap { item in
            if case let .stack(stack) = item {
                return stack
            }
            return nil
        }
    }

    /// The folders the app may read. Nothing while the Dock is off, and never a folder the owner has not added.
    var foldersToRead: [String] {
        isEnabled ? stacks.map(\.path) : []
    }
}

public extension DockLayout {
    /// Adds a stack after the others, once per folder.
    static func adding(_ stack: DockStack, to items: [DockItem]) -> [DockItem] {
        let isThere = items.contains { item in
            if case let .stack(existing) = item {
                return existing.path == stack.path
            }
            return false
        }
        return isThere ? items : items + [.stack(stack)]
    }

    static func setting(_ style: DockStackStyle, of stack: DockStack, in items: [DockItem]) -> [DockItem] {
        items.map { item in
            guard case let .stack(existing) = item, existing.id == stack.id else { return item }
            var updated = existing
            updated.style = style
            return .stack(updated)
        }
    }
}
