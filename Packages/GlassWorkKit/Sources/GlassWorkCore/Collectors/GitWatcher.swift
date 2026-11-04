import CoreServices
import Foundation

public enum GitChangeFilter {
    private static let noisy: Set<String> = ["build", "DerivedData", "dist", "node_modules", "target", "objects"]

    /// The repositories worth a new `git status`. FSEvents reports folders, so build output and
    /// tool folders are dropped here, otherwise a running build would re-read the repository all day.
    public static func repositories(changed paths: [String], in repositories: [String]) -> Set<String> {
        var result = Set<String>()
        for raw in paths {
            let path = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            guard let repository = repositories.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
                continue
            }
            let inside = path.dropFirst(repository.count).split(separator: "/")
            if !inside.contains(where: isNoisy) {
                result.insert(repository)
            }
        }
        return result
    }

    private static func isNoisy(_ folder: Substring) -> Bool {
        noisy.contains(String(folder)) || (folder.hasPrefix(".") && folder != ".git")
    }
}

/// Holds the callback for the C event stream.
private final class GitEventHandler: Sendable {
    let onChange: @Sendable ([String]) -> Void

    init(onChange: @escaping @Sendable ([String]) -> Void) {
        self.onChange = onChange
    }
}

private let receiveGitEvents: FSEventStreamCallback = { _, info, _, paths, _, _ in
    guard let info, let changed = unsafeBitCast(paths, to: NSArray.self) as? [String] else { return }
    Unmanaged<GitEventHandler>.fromOpaque(info).takeUnretainedValue().onChange(changed)
}

/// Watches repository folders with FSEvents.
@MainActor
final class GitWatcher {
    private var stream: FSEventStreamRef?
    private var handler: GitEventHandler?
    private var watched: [String] = []
    private let queue = DispatchQueue(label: "GlassWork.GitWatcher", qos: .utility)

    func watch(_ paths: [String], onChange: @escaping @Sendable ([String]) -> Void) {
        guard paths != watched else { return }
        stop()
        guard !paths.isEmpty else { return }
        let handler = GitEventHandler(onChange: onChange)
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(handler).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        guard let created = FSEventStreamCreate(
            nil,
            receiveGitEvents,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
        self.handler = handler
        watched = paths
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        handler = nil
        watched = []
    }
}
