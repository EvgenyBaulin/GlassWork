import Foundation

/// Finds command line tools. Apps start without the shell's PATH, so the usual folders are searched.
public enum ToolLocator {
    public typealias Check = @Sendable (String) -> Bool

    public static let isExecutable: Check = { FileManager.default.isExecutableFile(atPath: $0) }

    public static func find(
        _ name: String,
        home: String = NSHomeDirectory(),
        check: Check = isExecutable
    ) -> String? {
        let folders = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.docker/bin",
            "\(home)/.orbstack/bin",
            "\(home)/.rd/bin",
            "/usr/bin",
        ]
        return folders.map { "\($0)/\(name)" }.first(where: check)
    }

    /// `/usr/bin/git` is a stub that opens the Command Line Tools installer when they are missing,
    /// so it is used only when a real git stands behind it.
    public static func git(
        home: String = NSHomeDirectory(),
        check: Check = isExecutable
    ) -> String? {
        guard let path = find("git", home: home, check: check) else { return nil }
        guard path == "/usr/bin/git" else { return path }
        let real = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
        ]
        return real.contains(where: check) ? path : nil
    }
}
