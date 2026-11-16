import Foundation
import Observation

/// The shelf folder. It is a subfolder because the settings watcher reacts to anything written next
/// to settings.json. Copies live in `Files/<item id>/<original name>`, so two files with one name never
/// meet and the name stays right when the copy is dragged out. Only folders made here are ever deleted,
/// and the folder is found by the item's id, never by a path that may point at the user's own file.
actor ShelfDisk {
    private let folder: URL
    private let manager = FileManager.default

    init(folder: URL) {
        self.folder = folder
    }

    private var listURL: URL {
        folder.appending(path: "shelf.json", directoryHint: .notDirectory)
    }

    private var filesFolder: URL {
        folder.appending(path: "Files", directoryHint: .isDirectory)
    }

    /// The saved list; nil when the file exists but cannot be read, so its copies are left alone.
    func load() -> [ShelfItem]? {
        guard let data = try? Data(contentsOf: listURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([ShelfItem].self, from: data)
    }

    func save(_ items: [ShelfItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard (try? manager.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let data = try? encoder.encode(items) else { return }
        try? data.write(to: listURL, options: .atomic)
    }

    /// The copy, or nil when the file could not be copied.
    func copy(_ source: URL, id: UUID) -> URL? {
        let directory = filesFolder.appending(path: id.uuidString, directoryHint: .isDirectory)
        let target = directory.appending(path: source.lastPathComponent, directoryHint: .notDirectory)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: source, to: target)
            return target
        } catch {
            try? manager.removeItem(at: directory)
            return nil
        }
    }

    func deleteCopies(of ids: [UUID]) {
        for id in ids {
            try? manager.removeItem(at: filesFolder.appending(path: id.uuidString, directoryHint: .isDirectory))
        }
    }

    /// Removes copies left behind when the app quit between copying a file and saving the list.
    func deleteCopies(except kept: Set<UUID>) {
        let names = (try? manager.contentsOfDirectory(atPath: filesFolder.path(percentEncoded: false))) ?? []
        for name in names where !kept.contains(UUID(uuidString: name) ?? UUID()) {
            try? manager.removeItem(at: filesFolder.appending(path: name, directoryHint: .isDirectory))
        }
    }
}

/// The files on the shelf. The panel feeds it with drops; the files stay where they are unless the
/// setting says to copy them.
@MainActor
@Observable
public final class ShelfStore {
    /// Newest first.
    public private(set) var items: [ShelfItem] = []
    public private(set) var settings = ShelfSettings()

    @ObservationIgnored public let folder: URL
    @ObservationIgnored private let disk: ShelfDisk
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Called after the list changed, so the menu bar count follows at once.
    @ObservationIgnored public var onChange: (() -> Void)?

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GlassWork/Shelf", directoryHint: .isDirectory)
    }

    public init(folder: URL = ShelfStore.defaultFolder) {
        self.folder = folder
        disk = ShelfDisk(folder: folder)
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.byteCount }
    }

    /// Reads the list. Separate from `init`, so a monitor made in a test leaves the user's files alone.
    public func load() async {
        // An unreadable list keeps its copies on disk rather than treating every copy as left over.
        guard let stored = await disk.load() else { return }
        let present = stored.filter { Self.exists($0.path) }
        items = present
        await disk.deleteCopies(except: Set(present.map(\.id)))
        let overflow = trim()
        await disk.deleteCopies(of: overflow)
        if present.count != stored.count || !overflow.isEmpty {
            save()
        }
        onChange?()
    }

    public func apply(_ new: ShelfSettings) {
        guard new != settings else { return }
        settings = new
        discard(trim())
        save()
        onChange?()
    }

    /// Puts files on the shelf. Dropping one that is already there moves it to the front.
    public func add(_ urls: [URL], at date: Date = Date()) async {
        for url in urls where url.isFileURL && Self.exists(url.path(percentEncoded: false)) {
            let source = url.standardizedFileURL.path(percentEncoded: false)
            if let index = items.firstIndex(where: { $0.source == source }) {
                var item = items.remove(at: index)
                item.added = date
                items.insert(item, at: 0)
                continue
            }
            let id = UUID()
            var path = source
            if settings.copiesFiles {
                guard let copied = await disk.copy(url, id: id) else { continue }
                path = copied.path(percentEncoded: false)
            }
            items.insert(
                ShelfItem(
                    id: id,
                    name: url.lastPathComponent,
                    path: path,
                    source: source,
                    byteCount: Self.byteCount(at: url),
                    added: date,
                    kind: ShelfKind.of(url),
                    isCopy: settings.copiesFiles
                ),
                at: 0
            )
        }
        discard(trim())
        save()
        onChange?()
    }

    public func remove(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        discard([items.remove(at: index)].filter(\.isCopy).map(\.id))
        save()
        onChange?()
    }

    public func clearAll() {
        discard(items.filter(\.isCopy).map(\.id))
        items = []
        save()
        onChange?()
    }

    /// Drops what vanished from disk. Called when the panel opens, as files move while it is closed.
    public func refresh() {
        let present = items.filter { Self.exists($0.path) }
        guard present.count != items.count else { return }
        let gone = items.filter { !Self.exists($0.path) }.filter(\.isCopy).map(\.id)
        items = present
        discard(gone)
        save()
        onChange?()
    }

    /// Writes are finished, for tests that read the folder back.
    func flush() async {
        await saveTask?.value
    }

    /// Cuts the list to the limit and returns the ids of copies that went with it.
    private func trim() -> [UUID] {
        guard items.count > settings.maxItems else { return [] }
        let removed = items[settings.maxItems...]
        items = Array(items[..<settings.maxItems])
        return removed.filter(\.isCopy).map(\.id)
    }

    private func discard(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        Task { [disk] in await disk.deleteCopies(of: ids) }
    }

    private func save() {
        saveTask?.cancel()
        let snapshot = items
        saveTask = Task { [disk] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await disk.save(snapshot)
        }
    }

    private nonisolated static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private nonisolated static func byteCount(at url: URL) -> Int64 {
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? 0)
    }
}
