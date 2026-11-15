import Foundation

/// Codex's own app server (`codex app-server`, JSON-RPC over stdio). `account/rateLimits/read` returns the
/// limits Codex shows itself; GlassWork never reads `auth.json` or a token.
public enum CodexAppServer {
    public static let arguments = ["app-server"]
    public static let timeout: TimeInterval = 15
    private static let answerID = 2

    /// `initialize`, the `initialized` notification, then the request whose answer is wanted.
    public static func requests(clientVersion: String) -> [String] {
        let messages: [[String: Any]] = [
            [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": ["clientInfo": ["name": "GlassWork", "version": clientVersion]],
            ],
            ["jsonrpc": "2.0", "method": "initialized"],
            [
                "jsonrpc": "2.0",
                "id": answerID,
                "method": "account/rateLimits/read",
                "params": ["excludeResetCreditDetails": true],
            ],
        ]
        return messages.compactMap { message in
            (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) }
        }
    }

    private struct Envelope: Decodable {
        let id: Int?
    }

    /// The reply to the limits request, not a notification that happens to mention it.
    public static func isAnswer(_ line: String) -> Bool {
        (try? JSONDecoder().decode(Envelope.self, from: Data(line.utf8)))?.id == answerID
    }

    public static func usage(fromAnswer line: String, now: Date) -> AIToolUsage? {
        guard let answer = try? JSONDecoder().decode(CodexRateLimitsAnswer.self, from: Data(line.utf8)),
              let limits = answer.result?.rateLimits
        else { return nil }
        // Told apart by length, as in the session logs: which one is `primary` depends on the plan.
        let windows = [limits.primary, limits.secondary].compactMap { limit -> AIWindow? in
            guard let limit else { return nil }
            let kind: AIWindow.Kind? = switch limit.windowDurationMins {
            case 300: .fiveHour
            case 10080: .week
            default: nil
            }
            return kind.map {
                AIWindow(
                    kind: $0,
                    used: limit.usedPercent / 100,
                    resetsAt: limit.resetsAt.map(Date.init(timeIntervalSince1970:))
                )
            }
        }
        .sorted { $0.kind == .fiveHour && $1.kind != .fiveHour }
        guard !windows.isEmpty else { return nil }
        return AIToolUsage(tool: .codex, windows: windows, updatedAt: now, source: .tool)
    }
}

private struct CodexRateLimitsAnswer: Decodable {
    let result: CodexRateLimitsResult?
}

private struct CodexRateLimitsResult: Decodable {
    let rateLimits: CodexRateLimits?
}

private struct CodexRateLimits: Decodable {
    let primary: CodexRateLimit?
    let secondary: CodexRateLimit?
}

private struct CodexRateLimit: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Double?
}
