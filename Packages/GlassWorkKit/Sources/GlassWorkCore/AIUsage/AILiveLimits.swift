import Foundation

/// Asks Claude Code and Codex for their limits when their files go stale, and keeps whichever answer is newer.
///
/// Claude: `claude -p /usage`, only when `usage-latest.json` is older than 15 minutes (Claude is closed) and at
/// most once per 15 minutes; each call costs about 9 s of CPU. Codex: `codex app-server`, at most once per
/// 5 minutes. Neither call reads a token or the Keychain; both tools answer from their own login.
public actor AILiveLimits: AILimitProvider {
    public static let claudeInterval: TimeInterval = 15 * 60
    public static let codexInterval: TimeInterval = 5 * 60

    private let runner: ProcessRunning
    private let session: LineSessionRunning
    private let clientVersion: String
    private let locate: @Sendable (String) -> String?
    private let now: @Sendable () -> Date

    private var claudeLive: AIToolUsage?
    private var lastClaudeAttempt: Date?
    /// Set for good once `/usage` reaches the model: asking would then spend the limit it reads.
    private var claudeStopped = false
    private var codexLive: AIToolUsage?
    private var lastCodexAttempt: Date?

    public init(
        runner: ProcessRunning,
        session: LineSessionRunning,
        clientVersion: String,
        locate: @escaping @Sendable (String) -> String? = { ToolLocator.find($0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.runner = runner
        self.session = session
        self.clientVersion = clientVersion
        self.locate = locate
        self.now = now
    }

    public func refined(_ usage: AIToolUsage) async -> AIToolUsage {
        switch usage.tool {
        case .claudeCode: await refinedClaude(usage)
        case .codex: await refinedCodex(usage)
        default: usage
        }
    }

    private func refinedClaude(_ file: AIToolUsage) async -> AIToolUsage {
        let date = now()
        let fileIsFresh = file.updatedAt.map { date.timeIntervalSince($0) < Self.claudeInterval } ?? false
        // The attempt is noted before the call: the actor lets other reads in while it waits.
        if !fileIsFresh, !claudeStopped, Self.isDue(lastClaudeAttempt, Self.claudeInterval, at: date),
           let claude = locate("claude")
        {
            lastClaudeAttempt = date
            let output = try? await runner.run(
                claude,
                arguments: ClaudeUsageCommand.arguments,
                timeout: ClaudeUsageCommand.timeout
            )
            if let output, output.status == 0 {
                switch ClaudeUsageCommand.parse(output.stdout, now: date) {
                case let .usage(usage): claudeLive = usage
                case .spentTurns: claudeStopped = true
                case .unreadable: break
                }
            }
        }
        return Self.newer(file, claudeLive)
    }

    private func refinedCodex(_ file: AIToolUsage) async -> AIToolUsage {
        let date = now()
        if Self.isDue(lastCodexAttempt, Self.codexInterval, at: date), let codex = locate("codex") {
            lastCodexAttempt = date
            let answer = try? await session.exchange(
                codex,
                arguments: CodexAppServer.arguments,
                send: CodexAppServer.requests(clientVersion: clientVersion),
                until: CodexAppServer.isAnswer,
                timeout: CodexAppServer.timeout
            )
            if let usage = answer.flatMap({ CodexAppServer.usage(fromAnswer: $0, now: date) }) {
                codexLive = usage
            }
        }
        return Self.newer(file, codexLive)
    }

    private static func isDue(_ last: Date?, _ interval: TimeInterval, at date: Date) -> Bool {
        guard let last else { return true }
        return date.timeIntervalSince(last) >= interval || last > date
    }

    /// A file written after the tool was asked (the tool was opened again) wins; a live answer wins over a
    /// file that could not be read or has no limits.
    static func newer(_ file: AIToolUsage, _ live: AIToolUsage?) -> AIToolUsage {
        guard let live else { return file }
        if file.isUnreadable || file.windows.isEmpty {
            return live
        }
        return (file.updatedAt ?? .distantPast) > (live.updatedAt ?? .distantPast) ? file : live
    }
}
