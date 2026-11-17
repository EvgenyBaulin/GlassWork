import Foundation
import Observation

/// Live settings. Changes are saved right away, and hand edits of the file apply on the fly.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public private(set) var lastError: String?
    public private(set) var undoStack: [AppSettings] = []
    /// What ⌘Z took back, until the next change. A new change clears it.
    public private(set) var redoStack: [AppSettings] = []

    @ObservationIgnored public let backups: SettingsBackups
    @ObservationIgnored private let file: SettingsFile
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var fileWatcher: DispatchSourceFileSystemObject?

    private static let undoLimit = 50

    public init(file: SettingsFile = SettingsFile()) {
        self.file = file
        backups = SettingsBackups(directory: file.url.deletingLastPathComponent().appending(path: "Backups"))
        do {
            settings = try file.load() ?? AppSettings()
        } catch {
            settings = AppSettings()
            lastError = error.localizedDescription
        }
        watch()
    }

    /// With `undoable` false the change is also applied to the undo and redo snapshots,
    /// so ⌘Z neither steps over it nor brings the old value back.
    public func update(undoable: Bool = true, _ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        if undoable {
            pushUndo(settings)
            redoStack.removeAll()
        } else {
            undoStack = undoStack.map { var entry = $0; change(&entry); return entry }
            redoStack = redoStack.map { var entry = $0; change(&entry); return entry }
        }
        apply(copy)
    }

    /// Changes apply instantly, so ⌘Z is how a mistake gets reverted. Returns what changed back.
    @discardableResult
    public func undo() -> SettingsChange? {
        guard let previous = undoStack.popLast() else { return nil }
        let change = SettingsChange(from: settings, to: previous)
        redoStack.append(settings)
        apply(previous)
        return change
    }

    /// Takes back an undo. Returns what changed back.
    @discardableResult
    public func redo() -> SettingsChange? {
        guard let next = redoStack.popLast() else { return nil }
        let change = SettingsChange(from: settings, to: next)
        pushUndo(settings)
        apply(next)
        return change
    }

    /// Replaces everything, keeping a backup of what was there unless `backup` is false.
    public func replace(with new: AppSettings, backup: Bool = true) {
        if backup {
            backups.create(from: settings)
        }
        pushUndo(settings)
        redoStack.removeAll()
        apply(new)
    }

    private func pushUndo(_ previous: AppSettings) {
        undoStack.append(previous)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
    }

    private func apply(_ new: AppSettings) {
        settings = new
        do {
            try file.save(new)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reload() {
        do {
            guard let loaded = try file.load(), loaded != settings else { return }
            settings = loaded
            lastError = nil
        } catch {
            // A half-written or broken hand edit keeps the current settings until it is fixed.
            lastError = error.localizedDescription
        }
    }

    /// Watches the folder, which sees the file being replaced, and the file, which sees a write in place.
    /// Neither is enough alone: a save replaces the file, and `nano` or `open(path, "w")` write inside it.
    private func watch() {
        let folder = file.url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.watchFile()
                self?.reload()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
        watchFile()
    }

    /// A watch follows the file it was opened on, so every replacement needs a new one. The folder's event
    /// covers that, including a file that did not exist at launch. Before the first save there is nothing to open.
    private func watchFile() {
        fileWatcher?.cancel()
        fileWatcher = nil
        let descriptor = open(file.url.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        fileWatcher = source
    }
}
