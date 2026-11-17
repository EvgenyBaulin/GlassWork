import Foundation

public enum GitRepositoryList {
    /// The hand-added list without `path`, whether or not that repository can still be read.
    public static func removing(_ path: String, from manual: [String]) -> [String] {
        manual.filter { $0 != path }
    }
}
