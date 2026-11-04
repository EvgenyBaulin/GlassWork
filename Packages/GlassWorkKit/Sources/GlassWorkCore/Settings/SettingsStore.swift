import Foundation
import Observation

/// Live settings. Changes are saved right away, and hand edits of the file apply on the fly.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public private(set) var lastError: String?
    public private(set) var undoStack: [AppSettings] = []

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

    public func update(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        undoStack.append(settings)
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        apply(copy)
    }

    /// Changes apply instantly, so ⌘Z is how a mistake gets reverted.
    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        apply(previous)
    }

    /// Replaces everything, keeping a backup of what was there.
    public func replace(with new: AppSettings) {
        backups.create(from: settings)
        undoStack.append(settings)
        apply(new)
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
