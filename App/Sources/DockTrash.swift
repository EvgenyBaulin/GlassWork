import AppKit
import GlassWorkUI

/// The Trash at the end of the Dock: opens it, takes dropped files and empties it after asking.
@MainActor
final class DockTrash {
    private let onChange: (Bool) -> Void
    private var timer: Timer?

    /// Something else may fill or empty the Trash, so it is looked at now and then.
    private static let checkInterval: TimeInterval = 10

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    private static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".Trash", directoryHint: .isDirectory)
    }

    func start() {
        guard timer == nil else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Without Full Disk Access the folder may not list; the Dock then shows the empty icon.
    func check() {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        onChange(items.contains { $0 != ".DS_Store" })
    }

    var actions: DockTrashActions {
        DockTrashActions(
            open: { NSWorkspace.shared.open(Self.folder) },
            empty: { [weak self] in self?.empty() },
            moveToTrash: { [weak self] urls in
                for url in urls {
                    try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
                self?.check()
            }
        )
    }

    /// Finder empties it, as the system Dock does; macOS asks once to let GlassWork tell Finder.
    private func empty() {
        let alert = NSAlert()
        alert.messageText = loc("Empty the Trash?")
        alert.informativeText = loc("Items in the Trash will be deleted for good. This can’t be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc("Empty Trash"))
        alert.addButton(withTitle: loc("Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
        check()
    }
}
