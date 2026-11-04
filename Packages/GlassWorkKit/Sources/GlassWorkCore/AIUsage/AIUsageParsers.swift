import Foundation

private struct ClaudeFile: Decodable {
    let updatedAt: Double?
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at", fiveHour = "five_hour", sevenDay = "seven_day"
    }
}

private struct ClaudeWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage", resetsAt = "resets_at"
    }

    func window(_ kind: AIWindow.Kind) -> AIWindow {
        AIWindow(kind: kind, used: usedPercentage / 100, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
    }
}

/// `~/.claude/usage-latest.json`.
public enum ClaudeUsageParser {
    public static func usage(_ data: Data) -> AIToolUsage? {
        guard let file = try? JSONDecoder().decode(ClaudeFile.self, from: data) else { return nil }
        let windows = [file.fiveHour?.window(.fiveHour), file.sevenDay?.window(.week)].compactMap(\.self)
        return AIToolUsage(
            tool: .claudeCode,
            windows: windows,
            updatedAt: file.updatedAt.map(Date.init(timeIntervalSince1970:))
        )
    }
}

private struct CodexLine: Decodable {
    let timestamp: String?
    let payload: CodexPayload?
}

private struct CodexPayload: Decodable {
    let type: String?
    let rateLimits: CodexLimits?

    enum CodingKeys: String, CodingKey {
        case type, rateLimits = "rate_limits"
    }
}

private struct CodexLimits: Decodable {
    let primary: CodexLimit?
    let secondary: CodexLimit?
}

private struct CodexLimit: Decodable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent", windowMinutes = "window_minutes", resetsAt = "resets_at"
    }

    /// Windows are told apart by length; which one is `primary` depends on the plan.
    var window: AIWindow? {
        let kind: AIWindow.Kind? = switch windowMinutes {
        case 300: .fiveHour
        case 10080: .week
        default: nil
        }
        return kind.map {
            AIWindow(kind: $0, used: usedPercent / 100, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)))
        }
    }
}

/// Session logs in `~/.codex/sessions`. These also hold the conversation, so only `token_count`
/// lines are decoded and only their limit fields exist in the types above.
public enum CodexUsageParser {
    /// The latest limits in a session log, or nil when it has none.
    public static func usage(in text: String) -> AIToolUsage? {
        let decoder = JSONDecoder()
        for line in text.split(whereSeparator: \.isNewline).reversed() where line.contains("\"token_count\"") {
            guard let row = try? decoder.decode(CodexLine.self, from: Data(line.utf8)),
                  row.payload?.type == "token_count",
                  let limits = row.payload?.rateLimits
            else { continue }
            let windows = [limits.primary?.window, limits.secondary?.window]
                .compactMap(\.self)
                .sorted { $0.kind == .fiveHour && $1.kind != .fiveHour }
            guard !windows.isEmpty else { continue }
            return AIToolUsage(tool: .codex, windows: windows, updatedAt: row.timestamp.flatMap(date))
        }
        return nil
    }

    private static func date(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
}
