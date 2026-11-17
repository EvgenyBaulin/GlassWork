import Foundation

/// What makes a repository "to do" in the Git widget.
public enum GitToDo: String, Codable, CaseIterable, Sendable {
    /// Changes in the working folder that are not committed.
    case uncommitted
    /// Commits that are not pushed yet.
    case unpushed
    /// Any of those, or commits to pull.
    case both
}

/// Which repositories the Git widget lists.
public enum GitWidgetSource: String, Codable, CaseIterable, Sendable {
    case all
    /// Only the repository the Git module shows.
    case shared
    /// Only a repository chosen for the widget.
    case own
}

/// The widget's own choices, kept in settings.
public struct GitWidgetSettings: Codable, Sendable, Equatable {
    public var source = GitWidgetSource.all
    /// Used when `source` is `own`.
    public var repositoryPath: String?
    public var countsAs = GitToDo.both

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case source, repositoryPath, countsAs
    }

    /// A key missing from an older file, or a value this version does not know, reads as the default.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = (try? container.decodeIfPresent(GitWidgetSource.self, forKey: .source)) ?? .all
        repositoryPath = try? container.decodeIfPresent(String.self, forKey: .repositoryPath)
        countsAs = (try? container.decodeIfPresent(GitToDo.self, forKey: .countsAs)) ?? .both
    }

    /// The repository the widget reads on its own, so the Git module reads it too.
    public var ownRepository: String? {
        source == .own ? repositoryPath.flatMap { $0.isEmpty ? nil : $0 } : nil
    }

    /// What the widget extension gets: the one repository to show, if any, and what counts. `moduleSelection` is
    /// the repository chosen in the Git module.
    public func resolved(reading: GitReading?, moduleSelection: String?) -> WidgetGitOptions {
        switch source {
        case .all: WidgetGitOptions(path: nil, countsAs: countsAs)
        case .shared: WidgetGitOptions(path: reading?.selected(path: moduleSelection)?.path, countsAs: countsAs)
        case .own: WidgetGitOptions(path: ownRepository, countsAs: countsAs)
        }
    }
}

/// The part of the Git widget's settings that travels in the snapshot. A snapshot without it reads as the default.
public struct WidgetGitOptions: Codable, Sendable, Equatable {
    /// The only repository to list; nil lists them all.
    public var path: String?
    public var countsAs = GitToDo.both

    public init(path: String? = nil, countsAs: GitToDo = .both) {
        self.path = path
        self.countsAs = countsAs
    }

    /// The repositories the widget lists.
    public func shown(in repositories: [GitRepository]) -> [GitRepository] {
        guard let path else { return repositories }
        return repositories.filter { $0.path == path }
    }
}

public extension GitRepository {
    /// Whether the repository has something to do under the widget's rule.
    func needsWork(counting rule: GitToDo) -> Bool {
        guard let status else { return false }
        switch rule {
        case .uncommitted: return !status.isClean
        case .unpushed: return status.ahead > 0
        case .both: return needsWork
        }
    }
}
