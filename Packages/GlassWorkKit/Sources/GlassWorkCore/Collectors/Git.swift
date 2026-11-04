import Foundation

public struct GitStatus: Sendable, Equatable {
    /// Nil on a detached HEAD.
    public var branch: String?
    /// Nil before the first commit.
    public var commit: String?
    public var upstream: String?
    public var ahead = 0
    public var behind = 0
    public var changed = 0
    public var conflicted = 0

    public init() {}

    public var isClean: Bool {
        changed == 0 && conflicted == 0
    }

    /// The branch, or the short hash on a detached HEAD.
    public var head: String {
        branch ?? commit.map { String($0.prefix(7)) } ?? "—"
    }
}

public enum GitProblem: Sendable, Equatable {
    /// The folder was moved, deleted, or lost its `.git`.
    case missing
    /// In a folder macOS protects, so GlassWork leaves it alone.
    case needsPermission
    case failed
}

public struct GitRepository: Sendable, Equatable, Identifiable {
    public let path: String
    public var status: GitStatus?
    public var lastCommit: Date?
    public var problem: GitProblem?
    public var isManual = false

    public init(
        path: String,
        status: GitStatus? = nil,
        lastCommit: Date? = nil,
        problem: GitProblem? = nil,
        isManual: Bool = false
    ) {
        self.path = path
        self.status = status
        self.lastCommit = lastCommit
        self.problem = problem
        self.isManual = isManual
    }

    public var id: String {
        path
    }

    public var name: String {
        URL(filePath: path).lastPathComponent
    }
}

public enum GitReading: Sendable, Equatable {
    case notInstalled
    case repositories([GitRepository])

    public var repositories: [GitRepository] {
        if case let .repositories(repositories) = self {
            return repositories
        }
        return []
    }

    /// The repository shown in the menu bar: the chosen one, or the most recently committed to.
    public func selected(path: String?) -> GitRepository? {
        let readable = repositories.filter { $0.status != nil }
        return readable.first { $0.path == path } ?? readable.first
    }

    /// With a new status for the repositories that changed.
    public func updating(_ fresh: [GitRepository]) -> GitReading {
        let changed = Dictionary(fresh.map { ($0.path, $0) }, uniquingKeysWith: { _, last in last })
        return .repositories(GitRepository.sorted(repositories.map { changed[$0.path] ?? $0 }))
    }
}

extension GitRepository {
    /// Recent work first, repositories that cannot be read last.
    static func sorted(_ repositories: [GitRepository]) -> [GitRepository] {
        repositories.sorted { left, right in
            if (left.problem == nil) != (right.problem == nil) {
                return left.problem == nil
            }
            let leftDate = left.lastCommit ?? .distantPast
            let rightDate = right.lastCommit ?? .distantPast
            return leftDate == rightDate ? left.path < right.path : leftDate > rightDate
        }
    }
}

public enum GitStatusParser {
    /// `git status --porcelain=v2 --branch`. Only counts are kept, never file names.
    public static func parse(_ text: String) -> GitStatus {
        var status = GitStatus()
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            switch fields.first {
            case "#": header(fields, into: &status)
            case "1", "2", "?": status.changed += 1
            case "u": status.conflicted += 1
            default: continue
            }
        }
        return status
    }

    private static func header(_ fields: [Substring], into status: inout GitStatus) {
        guard fields.count >= 3 else { return }
        let value = String(fields[2])
        switch fields[1] {
        case "branch.oid": status.commit = value == "(initial)" ? nil : value
        case "branch.head": status.branch = value == "(detached)" ? nil : value
        case "branch.upstream": status.upstream = value
        case "branch.ab" where fields.count >= 4:
            status.ahead = abs(Int(fields[2]) ?? 0)
            status.behind = abs(Int(fields[3]) ?? 0)
        default: break
        }
    }

    /// `git log -1 --format=%ct`.
    public static func commitDate(_ text: String) -> Date? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)).map(Date.init(timeIntervalSince1970:))
    }
}

/// Folders macOS guards with a permission prompt. Reading anything inside would show one.
public enum ProtectedFolders {
    private static let inHome = [
        "Desktop",
        "Documents",
        "Downloads",
        "Library/Mobile Documents",
        "Movies",
        "Music",
        "Pictures",
    ]

    public static func contains(_ path: String, home: String) -> Bool {
        let protected = inHome.map { "\(home)/\($0)" } + ["/Volumes"]
        return protected.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

public enum GitDiscovery {
    private static let skipped: Set<String> = ["build", "DerivedData", "dist", "node_modules", "target", "vendor"]

    /// Repositories one or two levels below `root`.
    public static func repositories(in root: String, limit: Int = 60) -> [String] {
        var found: [String] = []
        for child in folders(in: root) {
            if isRepository(child) {
                found.append(child)
            } else {
                found += folders(in: child).filter(isRepository)
            }
        }
        return Array(found.prefix(limit))
    }

    /// A folder's path without the trailing slash URLs add.
    public static func plainPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    public static func isRepository(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path + "/.git")
    }

    private static func folders(in path: String) -> [String] {
        let url = URL(filePath: path)
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        return (contents ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !skipped.contains($0.lastPathComponent) }
            .map(plainPath)
            .sorted()
    }
}

/// Strictly read-only: `status` and `log` are the only subcommands ever run.
public struct GitCollector: Sendable {
    private let runner: ProcessRunning
    private let home: String
    private let locate: @Sendable () -> String?

    public init(
        runner: ProcessRunning,
        home: String = NSHomeDirectory(),
        locate: @escaping @Sendable () -> String? = { ToolLocator.git() }
    ) {
        self.runner = runner
        self.home = home
        self.locate = locate
    }

    public func read(manual: [String]) async -> GitReading {
        guard let git = locate() else { return .notInstalled }
        let discovered = GitDiscovery.repositories(in: "\(home)/Developer")
        var result: [GitRepository] = []
        for path in discovered where !manual.contains(path) {
            await result.append(repository(path, git: git, isManual: false))
        }
        for path in manual {
            await result.append(repository(path, git: git, isManual: true))
        }
        return .repositories(GitRepository.sorted(result))
    }

    public func refresh(_ repositories: [GitRepository]) async -> [GitRepository] {
        guard let git = locate() else { return [] }
        var result: [GitRepository] = []
        for item in repositories {
            await result.append(repository(item.path, git: git, isManual: item.isManual))
        }
        return result
    }

    private func repository(_ path: String, git: String, isManual: Bool) async -> GitRepository {
        guard !ProtectedFolders.contains(path, home: home) else {
            return GitRepository(path: path, problem: .needsPermission, isManual: isManual)
        }
        guard GitDiscovery.isRepository(path) else {
            return GitRepository(path: path, problem: .missing, isManual: isManual)
        }
        let status = try? await runner.run(
            git,
            arguments: Self.arguments(path, "status", "--porcelain=v2", "--branch"),
            timeout: 10
        )
        guard let status, status.status == 0 else {
            return GitRepository(path: path, problem: .failed, isManual: isManual)
        }
        let log = try? await runner.run(git, arguments: Self.arguments(path, "log", "-1", "--format=%ct"), timeout: 5)
        return GitRepository(
            path: path,
            status: GitStatusParser.parse(status.stdout),
            lastCommit: log.flatMap { GitStatusParser.commitDate($0.stdout) },
            isManual: isManual
        )
    }

    /// `--no-optional-locks` keeps `status` from rewriting `.git/index`, which would change someone
    /// else's repository and wake the file watcher. A repository's own config cannot start a
    /// monitor program either.
    static func arguments(_ path: String, _ command: String...) -> [String] {
        ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", path] + command
    }
}
