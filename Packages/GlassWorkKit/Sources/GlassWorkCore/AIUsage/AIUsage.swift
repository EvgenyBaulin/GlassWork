import Foundation

public enum AITool: String, Codable, CaseIterable, Sendable, Identifiable {
    case claudeCode, codex, geminiCLI, openCode, copilotCLI, droid

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        case .copilotCLI: "Copilot CLI"
        case .droid: "Droid"
        }
    }

    /// Letter on the tool's badge.
    public var initial: String {
        switch self {
        case .claudeCode: "C"
        case .codex: "X"
        case .geminiCLI: "G"
        case .openCode: "O"
        case .copilotCLI: "P"
        case .droid: "D"
        }
    }
}

public struct AIWindow: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case fiveHour, week
        /// A plan's monthly allowance, such as Copilot's.
        case month
    }

    public let kind: Kind
    /// Share of the limit used when the tool last wrote it, from 0 to 1.
    public let used: Double
    public let resetsAt: Date?

    public init(kind: Kind, used: Double, resetsAt: Date?) {
        self.kind = kind
        self.used = used
        self.resetsAt = resetsAt
    }

    /// Files stop changing when a tool is idle, so a window past its reset is empty again.
    public func used(at date: Date) -> Double {
        if let resetsAt, resetsAt <= date {
            return 0
        }
        return used
    }
}

/// Where the numbers of a tool came from.
public enum AIUsageSource: String, Codable, Sendable {
    /// The tool's own files on this Mac.
    case files
    /// The tool itself, asked by GlassWork: `claude -p /usage` or `codex app-server`.
    case tool
}

public struct AIToolUsage: Codable, Sendable, Equatable, Identifiable {
    public let tool: AITool
    public var windows: [AIWindow]
    public var updatedAt: Date?
    /// True when usage files exist but could not be read.
    public var isUnreadable: Bool
    /// nil = read from the tool's files, as in snapshots saved before the tools were asked directly.
    public var source: AIUsageSource?
    public var spend: AISpend?

    public init(
        tool: AITool,
        windows: [AIWindow] = [],
        updatedAt: Date? = nil,
        isUnreadable: Bool = false,
        source: AIUsageSource? = nil,
        spend: AISpend? = nil
    ) {
        self.tool = tool
        self.windows = windows
        self.updatedAt = updatedAt
        self.isUnreadable = isUnreadable
        self.source = source
        self.spend = spend
    }

    public var id: AITool {
        tool
    }

    public func peak(at date: Date) -> AIWindow? {
        windows.max { $0.used(at: date) < $1.used(at: date) }
    }
}

/// Which limit the menu bar shows.
public enum AIUsageWindowChoice: String, Sendable, CaseIterable {
    case highest, fiveHour, week
}

public enum AIUsageOption {
    public static let window = "window"
    public static let warnPercent = "warnAt"
    public static let defaultWarnPercent = 90

    public static func warnShare(_ options: [String: String]) -> Double {
        Double(min(max(options.number(warnPercent, default: defaultWarnPercent), 1), 100)) / 100
    }
}

public struct AIUsageReading: Codable, Sendable, Equatable {
    /// Share of a limit that turns the module orange, unless Settings says otherwise.
    public static let alertShare = 0.9

    /// What Settings says. Part of the reading, so widgets follow it too.
    public private(set) var warnShare: Double?

    public var warnLevel: Double {
        warnShare ?? Self.alertShare
    }

    public func warning(at share: Double) -> AIUsageReading {
        var reading = self
        reading.warnShare = share
        return reading
    }

    /// Tools found on this Mac, in display order.
    public let tools: [AIToolUsage]
    public let readAt: Date

    public init(tools: [AIToolUsage], readAt: Date) {
        self.tools = tools
        self.readAt = readAt
    }

    /// True when at least one tool was asked directly rather than read from its files.
    public var isLive: Bool {
        tools.contains { $0.source == .tool }
    }

    public var missing: [AITool] {
        AITool.allCases.filter { tool in !tools.contains { $0.tool == tool } }
    }

    /// The tool and window closest to their limit.
    public func peak(at date: Date) -> (tool: AITool, window: AIWindow)? {
        let candidates = tools.compactMap { usage in
            usage.peak(at: date).map { (tool: usage.tool, window: $0) }
        }
        return candidates.max { $0.window.used(at: date) < $1.window.used(at: date) }
    }

    /// The same among one kind of window. A tool that reports only the other kind still shows something.
    public func peak(at date: Date, choice: AIUsageWindowChoice) -> (tool: AITool, window: AIWindow)? {
        let kind: AIWindow.Kind? = switch choice {
        case .highest: nil
        case .fiveHour: .fiveHour
        case .week: .week
        }
        guard let kind else { return peak(at: date) }
        let candidates = tools.flatMap { usage in
            usage.windows.filter { $0.kind == kind }.map { (tool: usage.tool, window: $0) }
        }
        return candidates.max { $0.window.used(at: date) < $1.window.used(at: date) } ?? peak(at: date)
    }
}

public extension AIToolUsage {
    /// Limits or spend to show, as opposed to "can't read" or "no usage yet".
    var hasNumbers: Bool {
        !windows.isEmpty || spend != nil
    }
}

public extension AIUsageReading {
    /// A read that misses something keeps the tool's last limits or spend, so a file caught mid-write or a
    /// request that failed does not blank the row. The row still says how old the numbers are, and the next
    /// read tries again as usual.
    func keepingKnown(from previous: AIUsageReading?) -> AIUsageReading {
        guard let previous else { return self }
        let merged = tools.map { usage in
            guard let known = previous.tools.first(where: { $0.tool == usage.tool }), known.hasNumbers else {
                return usage
            }
            guard usage.hasNumbers else { return known }
            var kept = usage
            if kept.windows.isEmpty {
                kept.windows = known.windows
            }
            if kept.spend == nil {
                kept.spend = known.spend
            }
            return kept
        }
        var reading = AIUsageReading(tools: merged, readAt: readAt)
        reading.warnShare = warnShare
        return reading
    }
}
