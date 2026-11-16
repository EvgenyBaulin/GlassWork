import Foundation
import GlassWorkCore

/// Notices Xcode builds for the island: a running one from the process list, its outcome from Xcode's log store.
/// It polls only while the island is on, and reads a log manifest only after a build has ended.
@MainActor
final class BuildWatcher {
    /// Called whenever `reading` changes.
    var onChange: () -> Void = {}
    private(set) var reading: BuildReading? {
        didSet {
            if reading != oldValue {
                onChange()
            }
        }
    }

    private var task: Task<Void, Never>?
    private var run: BuildRun?
    private var quietPolls = 0
    private var manifests = ManifestIndex()
    private let runner: ProcessRunning = ProcessRunner()

    func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard task == nil else { return }
            task = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } else {
            task?.cancel()
            task = nil
            run = nil
            reading = nil
        }
    }

    private func poll() async {
        let processes = await ProcessList.read(using: runner)
        guard !Task.isCancelled else { return }
        let isBuilding = BuildProcesses.isBuilding(processes)
        if isBuilding, run == nil {
            // A result from the previous build gives way to the new one.
            let started = await BuildRun(name: scheme(of: processes), started: Date())
            run = started
            reading = .running(started)
            quietPolls = 0
        } else if isBuilding {
            quietPolls = 0
        } else if let ended = run {
            // Compilers pause between files, so a build ends only after two quiet polls in a row.
            quietPolls += 1
            guard quietPolls >= 2 else { return }
            run = nil
            quietPolls = 0
            reading = await outcome(of: ended)
        }
    }

    /// Only `xcodebuild` names its scheme on the command line, and it is asked once per build.
    private func scheme(of processes: [ProcessUsage]) async -> String? {
        guard let pid = BuildProcesses.builderPID(processes),
              let output = try? await runner.run(
                  "/bin/ps",
                  arguments: ["-p", "\(pid)", "-ww", "-o", "args="],
                  timeout: 2
              )
        else { return nil }
        return BuildProcesses.scheme(fromArguments: output.stdout)
    }

    /// The log store is written as the build ends, a moment after its process may have gone.
    private func outcome(of ended: BuildRun) async -> BuildReading? {
        for delay in [0.5, 2, 4] {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return nil }
            let index = manifests
            let (found, refreshed) = await Task.detached { index.result(for: ended) }.value
            manifests = refreshed
            if let found {
                return .finished(found)
            }
        }
        return nil
    }
}

/// The manifests of every project's build log store, found by listing DerivedData at most once a minute.
private struct ManifestIndex: Sendable {
    private var paths: [URL] = []
    private var listed = Date.distantPast
    private static let root = URL.homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData")

    /// Reads only the manifests changed since the build began, and lists DerivedData again when the list is old.
    func result(for run: BuildRun) -> (BuildResult?, ManifestIndex) {
        var index = self
        if Date().timeIntervalSince(listed) > 60 {
            index.list()
        }
        let entries = index.paths.flatMap { url -> [BuildLogEntry] in
            let changed = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let changed, changed >= run.started.addingTimeInterval(-2),
                  let data = try? Data(contentsOf: url) else { return [] }
            return BuildManifest.parse(data)
        }
        return (BuildManifest.result(for: run, in: entries), index)
    }

    private mutating func list() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: Self.root, includingPropertiesForKeys: nil
        )) ?? []
        paths = folders.map { $0.appending(path: "Logs/Build/LogStoreManifest.plist") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        listed = Date()
    }
}
