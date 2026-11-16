import AppKit
import GlassWorkCore
import Observation

/// Why a volume would not eject, in words for the panel.
enum EjectFailure {
    /// `In use by Finder` when macOS names the program holding the volume, `Could not eject` otherwise.
    static func message(for error: NSError, appName: (Int32) -> String?) -> String {
        let pid = (error.userInfo[NSFileManagerUnmountDissentingProcessIdentifierErrorKey] as? NSNumber)?.int32Value
        if let pid, let name = appName(pid) {
            return loc("In use by \(name)")
        }
        return loc("Could not eject")
    }
}

/// Ejects that are running or have failed, read by the panel and the menu bar item.
@MainActor
@Observable
final class EjectActivity {
    static let shared = EjectActivity()

    /// Volume paths being ejected right now.
    private(set) var ejecting: Set<String> = []
    /// Volume path to the reason its last eject failed. Cleared by the next try.
    private(set) var failures: [String: String] = [:]

    func eject(_ volumes: [DiskVolume], finished: @escaping @MainActor () -> Void) {
        for volume in volumes where !ejecting.contains(volume.path) {
            ejecting.insert(volume.path)
            failures[volume.path] = nil
            let path = volume.path
            FileManager.default.unmountVolume(
                at: URL(filePath: path),
                options: [.allPartitionsAndEjectDisk, .withoutUI]
            ) { error in
                let reason = error.map {
                    EjectFailure
                        .message(for: $0 as NSError) { NSRunningApplication(processIdentifier: $0)?.localizedName }
                }
                Task { @MainActor in
                    self.ejecting.remove(path)
                    self.failures[path] = reason
                    finished()
                }
            }
        }
    }

    /// Forgets failures of volumes that are gone.
    func forget(except present: [DiskVolume]) {
        let paths = Set(present.map(\.path))
        failures = failures.filter { paths.contains($0.key) }
    }
}
