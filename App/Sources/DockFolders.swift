import AppKit
import GlassWorkCore

/// Keeps what is in the Dock's stacks up to date.
///
/// Told only about folders the owner has added: opening Downloads, Documents or Desktop can raise a macOS prompt.
/// A folder reports files arriving and leaving by itself, but not a file growing, so it is read again every
/// second only while a download is under way.
@MainActor
final class DockFolders {
    private var sources: [String: any DispatchSourceFileSystemObject] = [:]
    private var files: [String: [DockFile]] = [:]
    private var following: Task<Void, Never>?
    private let onChange: ([String: [DockFile]]) -> Void

    init(onChange: @escaping ([String: [DockFile]]) -> Void) {
        self.onChange = onChange
    }

    func watch(_ paths: [String]) {
        let wanted = Set(paths)
        for (path, source) in sources where !wanted.contains(path) {
            source.cancel()
            sources[path] = nil
            files[path] = nil
        }
        for path in wanted where sources[path] == nil {
            start(path)
        }
        onChange(files)
        followDownloads()
    }

    /// Moves a download that is not finished to the Trash and takes it off the lists at once.
    func cancel(_ path: String) {
        NSWorkspace.shared.recycle([URL(filePath: path)]) { [weak self] _, error in
            guard error == nil else { return }
            Task { @MainActor in
                guard let folders = self else { return }
                folders.files = folders.files.mapValues { $0.filter { $0.path != path } }
                folders.onChange(folders.files)
            }
        }
    }

    private func start(_ path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.read(path) }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources[path] = source
        read(path)
    }

    private func read(_ path: String) {
        Task { [weak self] in
            let found = await Task.detached { DockFolderReader().read(path) }.value
            guard let self, sources[path] != nil else { return }
            files[path] = found
            onChange(files)
            followDownloads()
        }
    }

    private func followDownloads() {
        let isDownloading = files.values.contains { $0.contains(where: \.isDownloading) }
        guard isDownloading != (following != nil) else { return }
        following?.cancel()
        following = nil
        guard isDownloading else { return }
        following = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                sources.keys.forEach(read)
            }
        }
    }
}

extension NSRunningApplication {
    /// The app as the Dock keeps it, for apps with a window of their own. GlassWork itself is left out.
    var dockApp: DockApp? {
        guard activationPolicy == .regular, self != .current, let url = bundleURL, url.pathExtension == "app" else {
            return nil
        }
        return DockApp(
            path: url.path(percentEncoded: false),
            name: localizedName ?? url.deletingPathExtension().lastPathComponent
        )
    }
}
