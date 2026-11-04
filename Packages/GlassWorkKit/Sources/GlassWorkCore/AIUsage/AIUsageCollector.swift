import Foundation

/// Where exact limits will come from once a server request exists.
///
/// Today usage comes from local files only: nothing here reads a token or the Keychain or opens a
/// connection. A later implementation can ask the tool's server and return a corrected usage;
/// `AIUsageCollector` calls this for every tool it found and needs no other change.
public protocol AILimitProvider: Sendable {
    func refined(_ usage: AIToolUsage) async -> AIToolUsage
}

/// The default: local numbers stand as they are.
public struct LocalFilesOnly: AILimitProvider {
    public init() {}

    public func refined(_ usage: AIToolUsage) async -> AIToolUsage {
        usage
    }
}

/// Reads usage counters from the tools' own files. Other files in their folders, such as login
/// details, are never opened; a tool without a known usage file is only checked for presence.
public struct AIUsageCollector: Sendable {
    private let runner: ProcessRunning
    private let home: URL
    private let limits: AILimitProvider
    private let locate: @Sendable (String) -> String?

    /// Session logs tried before giving up on finding limits.
    private static let logsToScan = 5
    /// Logs larger than this are skipped, because they are read whole.
    private static let largestLog = 16 * 1024 * 1024

    public init(
        runner: ProcessRunning,
        home: String = NSHomeDirectory(),
        limits: AILimitProvider = LocalFilesOnly(),
        locate: @escaping @Sendable (String) -> String? = { ToolLocator.find($0) }
    ) {
        self.runner = runner
        self.home = URL(filePath: home)
        self.limits = limits
        self.locate = locate
    }

    public func read(at date: Date = Date()) async -> AIUsageReading {
        var tools: [AIToolUsage] = []
        for tool in AITool.allCases where isInstalled(tool) {
            await tools.append(limits.refined(usage(of: tool)))
        }
        return AIUsageReading(tools: tools, readAt: date)
    }

    private func isInstalled(_ tool: AITool) -> Bool {
        let (paths, command): ([String], String) = switch tool {
        case .claudeCode: ([".claude/usage-latest.json", ".claude/projects"], "claude")
        case .codex: ([".codex/sessions"], "codex")
        // A bare `~/.gemini` also appears with other Google tools.
        case .geminiCLI: ([".gemini/settings.json", ".gemini/tmp"], "gemini")
        case .openCode: ([".local/share/opencode", ".config/opencode"], "opencode")
        case .copilotCLI: ([".copilot"], "copilot")
        case .droid: ([".factory"], "droid")
        }
        let exists = paths.contains { FileManager.default.fileExists(atPath: home.appending(path: $0).path) }
        return exists || locate(command) != nil
    }

    private func usage(of tool: AITool) async -> AIToolUsage {
        switch tool {
        case .claudeCode: claudeUsage()
        case .codex: await codexUsage()
        default: AIToolUsage(tool: tool)
        }
    }

    private func claudeUsage() -> AIToolUsage {
        let file = home.appending(path: ".claude/usage-latest.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return AIToolUsage(tool: .claudeCode) }
        guard let data = try? Data(contentsOf: file), let usage = ClaudeUsageParser.usage(data) else {
            return AIToolUsage(tool: .claudeCode, isUnreadable: true)
        }
        return usage
    }

    private func codexUsage() async -> AIToolUsage {
        var isUnreadable = false
        for log in Self.newestLogs(in: home.appending(path: ".codex/sessions"), limit: Self.logsToScan) {
            guard let text = await text(of: log) else {
                isUnreadable = true
                continue
            }
            if let usage = CodexUsageParser.usage(in: text) {
                return usage
            }
        }
        return AIToolUsage(tool: .codex, isUnreadable: isUnreadable)
    }

    private func text(of log: URL) async -> String? {
        let size = (try? log.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= Self.largestLog else { return nil }
        guard log.pathExtension == "zst" else {
            return (try? Data(contentsOf: log)).map { String(decoding: $0, as: UTF8.self) }
        }
        // The system has no zstd decoder; the logs stay unread on a Mac without the command.
        guard let zstd = locate("zstd") else { return nil }
        let arguments = ["-dc", "--", log.path(percentEncoded: false)]
        let output = try? await runner.run(zstd, arguments: arguments, timeout: 10)
        return output?.status == 0 ? output?.stdout : nil
    }

    /// Logs live in `YYYY/MM/DD` folders and their names start with the time, so names sort by age.
    static func newestLogs(in root: URL, limit: Int) -> [URL] {
        var result: [URL] = []
        for year in folders(in: root) {
            for month in folders(in: year) {
                for day in folders(in: month) {
                    result += contents(of: day).filter(isLog)
                    if result.count >= limit {
                        return Array(result.prefix(limit))
                    }
                }
            }
        }
        return result
    }

    private static func isLog(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix("rollout-") && (name.hasSuffix(".jsonl") || name.hasSuffix(".jsonl.zst"))
    }

    private static func folders(in url: URL) -> [URL] {
        contents(of: url).filter(\.hasDirectoryPath)
    }

    private static func contents(of url: URL) -> [URL] {
        let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return (items ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
}
