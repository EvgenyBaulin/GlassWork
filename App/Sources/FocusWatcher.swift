import Foundation
import GlassWorkCore

/// Follows the system's Focus state for the island. The state is read from the Focus files once at start and
/// then only when the system says it changed: a distributed notification, or a write in the files' folder.
/// A slow timer checks the file's date as a fallback, and parses only when that date moved.
@MainActor
final class FocusWatcher {
    /// Nil until the first read, and when the files cannot be read (Full Disk Access is missing).
    private(set) var reading: FocusReading?

    private let directory: URL
    private var onChange: (() -> Void)?
    private var isRunning = false
    private var observer: (any NSObjectProtocol)?
    private var folderSource: (any DispatchSourceFileSystemObject)?
    private var fallback: Timer?
    private var debounce: Task<Void, Never>?
    private var lastModified: Date?

    private static let notificationName = Notification.Name("com.apple.donotdisturb.state.changed")
    private static let fallbackInterval: TimeInterval = 30

    init(directory: URL = FocusFiles.defaultDirectory) {
        self.directory = directory
    }

    /// Starts or stops with the island setting; calling it again with the same value does nothing.
    func setEnabled(_ enabled: Bool, onChange: @escaping () -> Void) {
        guard enabled != isRunning else { return }
        if enabled {
            start(onChange: onChange)
        } else {
            stop()
        }
    }

    func stop() {
        isRunning = false
        onChange = nil
        debounce?.cancel()
        debounce = nil
        fallback?.invalidate()
        fallback = nil
        folderSource?.cancel()
        folderSource = nil
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        reading = nil
        lastModified = nil
    }

    private func start(onChange: @escaping () -> Void) {
        isRunning = true
        self.onChange = onChange
        refresh(notify: false)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        watchFolder()
        fallback = Timer.scheduledTimer(withTimeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfFileMoved() }
        }
    }

    private func watchFolder() {
        let descriptor = open(directory.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.refreshIfFileMoved() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        folderSource = source
    }

    /// The system writes the files a moment after it announces a change.
    private func scheduleRefresh() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refresh(notify: true)
        }
    }

    private func refreshIfFileMoved() {
        guard FocusFiles.modificationDate(in: directory) != lastModified else { return }
        scheduleRefresh()
    }

    private func refresh(notify: Bool) {
        guard isRunning else { return }
        lastModified = FocusFiles.modificationDate(in: directory)
        let new = FocusFiles.read(in: directory)
        guard new != reading else { return }
        reading = new
        if notify {
            onChange?()
        }
    }
}
