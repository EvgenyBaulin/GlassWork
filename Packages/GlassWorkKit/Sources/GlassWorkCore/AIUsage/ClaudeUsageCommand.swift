import Foundation

/// Claude Code's own `/usage` command, run as `claude -p /usage`. It answers locally, without a model turn,
/// so asking costs no limit; GlassWork never touches the login or a token.
public enum ClaudeUsageCommand {
    /// `--no-session-persistence`: otherwise each call leaves a session log behind.
    public static let arguments = ["-p", "/usage", "--no-session-persistence", "--output-format", "json"]
    public static let timeout: TimeInterval = 30

    public enum Result: Equatable, Sendable {
        case usage(AIToolUsage)
        /// The command reached the model and so spent the limit it was meant to read.
        case spentTurns
        case unreadable
    }

    public static func parse(_ stdout: String, now: Date) -> Result {
        guard let output = try? JSONDecoder().decode(ClaudeUsageOutput.self, from: Data(stdout.utf8))
        else { return .unreadable }
        if (output.numTurns ?? 0) > 0 || (output.totalCostUSD ?? 0) > 0 {
            return .spentTurns
        }
        guard let text = output.result else { return .unreadable }
        var windows: [AIWindow] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if let window = window(String(line), now: now), !windows.contains(where: { $0.kind == window.kind }) {
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { return .unreadable }
        windows.sort { $0.kind == .fiveHour && $1.kind != .fiveHour }
        return .usage(AIToolUsage(tool: .claudeCode, windows: windows, updatedAt: now, source: .tool))
    }

    /// `Current session: 47% used · resets Nov 16 at 3:20am (Europe/Moscow)`
    /// `Current week (all models): 5% used · resets 8:10pm (Europe/Moscow)`
    /// Lines for one model, such as `Current week (Fable)`, are not the overall limit and are skipped.
    private nonisolated(unsafe) static let pattern = #/
    ^Current\ (session|week\ \(all\ models\)):\ <?(\d+)%\ used
    (?:\ ·\ resets\ (?:([A-Z][a-z]{2})\ (\d{1,2})\ at\ )?(\d{1,2})(?::(\d{2}))?(am|pm)\ \(([^)]+)\))?
    /#

    static func window(_ line: String, now: Date) -> AIWindow? {
        guard let match = line.firstMatch(of: pattern), let percent = Double(match.2) else { return nil }
        let kind: AIWindow.Kind = match.1 == "session" ? .fiveHour : .week
        var resetsAt: Date?
        if let hour = match.5.flatMap({ Int($0) }), let half = match.7, let zone = match.8 {
            let day = match.3.flatMap { month in match.4.flatMap { Int($0) }.map { (month: String(month), day: $0) } }
            resetsAt = date(
                on: day,
                hour: hour % 12 + (half == "pm" ? 12 : 0),
                minute: match.6.flatMap { Int($0) } ?? 0,
                zone: String(zone),
                now: now
            )
        }
        return AIWindow(kind: kind, used: percent / 100, resetsAt: resetsAt)
    }

    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// A reset is at most a week away. A date without a year takes the year that puts it nearest to now, so
    /// `Jan 2` seen on Dec 30 is next year; a time without a date is today or, once past, tomorrow.
    private static func date(
        on day: (month: String, day: Int)?,
        hour: Int,
        minute: Int,
        zone: String,
        now: Date
    ) -> Date? {
        guard let timeZone = TimeZone(identifier: zone) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = hour
        parts.minute = minute
        if let day {
            guard let index = months.firstIndex(of: day.month), let year = parts.year else { return nil }
            parts.month = index + 1
            parts.day = day.day
            let candidates = [year - 1, year, year + 1].compactMap { candidate -> Date? in
                parts.year = candidate
                return calendar.date(from: parts)
            }
            return candidates.min { abs($0.timeIntervalSince(now)) < abs($1.timeIntervalSince(now)) }
        }
        guard let date = calendar.date(from: parts) else { return nil }
        return date < now ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }
}

private struct ClaudeUsageOutput: Decodable {
    let result: String?
    let numTurns: Int?
    let totalCostUSD: Double?

    enum CodingKeys: String, CodingKey {
        case result, numTurns = "num_turns", totalCostUSD = "total_cost_usd"
    }
}
