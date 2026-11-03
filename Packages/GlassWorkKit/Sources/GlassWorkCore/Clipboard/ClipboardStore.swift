import Foundation
import Observation

/// The history folder. It is a subfolder because the settings watcher reacts to anything written next
/// to settings.json. Not encrypted, as decided for this module; only this user can open it.
actor ClipboardDisk {
    private let folder: URL
    private let manager = FileManager.default

    init(folder: URL) {
        self.folder = folder
    }

    private var historyURL: URL {
        folder.appending(path: "history.json", directoryHint: .notDirectory)
    }

    private var imagesFolder: URL {
        folder.appending(path: "Images", directoryHint: .isDirectory)
    }

    func load() -> ClipboardHistory {
        guard let data = try? Data(contentsOf: historyURL) else { return ClipboardHistory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ClipboardHistory.self, from: data)) ?? ClipboardHistory()
    }

    func save(_ history: ClipboardHistory) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard prepare(), let data = try? encoder.encode(history) else { return }
        write(data, to: historyURL)
    }

    func saveImage(_ data: Data, named name: String) {
        guard prepare() else { return }
        write(data, to: imagesFolder.appending(path: name, directoryHint: .notDirectory))
    }

    func deleteImages(_ names: [String]) {
        for name in names {
            try? manager.removeItem(at: imagesFolder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    /// Removes images left behind when the app quit between writing one and saving the history.
    func deleteImages(except kept: Set<String>) {
        let names = (try? manager.contentsOfDirectory(atPath: imagesFolder.path(percentEncoded: false))) ?? []
        deleteImages(names.filter { !kept.contains($0) })
    }

    private func prepare() -> Bool {
        let owner: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        return (try? manager.createDirectory(
            at: imagesFolder,
            withIntermediateDirectories: true,
            attributes: owner
        )) != nil
    }

    private func write(_ data: Data, to url: URL) {
        try? data.write(to: url, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
    }
}

/// The clipboard history shown by the panels. The app feeds it; it never reads the pasteboard itself.
@MainActor
@Observable
public final class ClipboardStore {
    public private(set) var history = ClipboardHistory()
    public private(set) var settings = ClipboardSettings()
    public private(set) var lastCapture: Date?
    /// The user set this app to "Don't Allow" for pasteboard access in System Settings.
    public var isAccessDenied = false

    @ObservationIgnored public let folder: URL
    @ObservationIgnored private let disk: ClipboardDisk
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastPrune = Date.distantPast

    public static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GlassWork/Clipboard", directoryHint: .isDirectory)
    }

    public init(folder: URL = ClipboardStore.defaultFolder) {
        self.folder = folder
        disk = ClipboardDisk(folder: folder)
    }

    /// Reads the history. Separate from `init`, so a monitor made in a test leaves the user's files alone.
    public func load(at date: Date = Date()) async {
        history = await disk.load()
        await disk.deleteImages(except: Set(history.entries.compactMap(\.imageName)))
        prune(at: date)
    }

    public func apply(_ new: ClipboardSettings) {
        guard new != settings else { return }
        let retentionChanged = new.retentionDays != settings.retentionDays
        settings = new
        if retentionChanged {
            prune(at: Date())
        }
    }

    public func add(_ capture: ClipboardCapture) {
        let image = capture.image
        let name = capture.entry.imageName
        let replaced = history.insert(capture.entry)
        lastCapture = capture.entry.date
        let unused = [replaced?.imageName].compactMap(\.self)
        Task { [disk] in
            if let image, let name {
                await disk.saveImage(image, named: name)
            }
            await disk.deleteImages(unused)
        }
        prune(at: capture.entry.date)
        save()
    }

    public func togglePin(_ entry: ClipboardEntry) {
        history.togglePin(entry.id)
        save()
    }

    public func delete(_ entry: ClipboardEntry) {
        let removed = history.remove(entry.id)
        discard([removed].compactMap(\.self))
        save()
    }

    public func clearAll() {
        discard(history.removeUnpinned())
        save()
    }

    public func imageURL(for entry: ClipboardEntry) -> URL? {
        entry.imageName.map {
            folder.appending(path: "Images", directoryHint: .isDirectory)
                .appending(path: $0, directoryHint: .notDirectory)
        }
    }

    /// Called on every monitor read. Old entries only need checking now and then.
    public func tick(at date: Date) {
        guard date.timeIntervalSince(lastPrune) >= 3600 else { return }
        prune(at: date)
    }

    /// Writes are finished, for tests that read the folder back.
    func flush() async {
        await saveTask?.value
    }

    private func prune(at date: Date) {
        lastPrune = date
        let removed = history.prune(at: date, retentionDays: settings.retentionDays)
        guard !removed.isEmpty else { return }
        discard(removed)
        save()
    }

    private func discard(_ entries: [ClipboardEntry]) {
        let names = entries.compactMap(\.imageName)
        guard !names.isEmpty else { return }
        Task { [disk] in await disk.deleteImages(names) }
    }

    /// A burst of copies ends in one write.
    private func save() {
        saveTask?.cancel()
        let snapshot = history
        saveTask = Task { [disk] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await disk.save(snapshot)
        }
    }
}
