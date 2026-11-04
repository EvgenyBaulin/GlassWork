import Foundation

public enum AITool: String, CaseIterable, Sendable, Identifiable {
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

public struct AIWindow: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case fiveHour, week
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

public struct AIToolUsage: Sendable, Equatable, Identifiable {
    public let tool: AITool
    public var windows: [AIWindow]
    public var updatedAt: Date?
    /// True when usage files exist but could not be read.
    public var isUnreadable: Bool

    public init(tool: AITool, windows: [AIWindow] = [], updatedAt: Date? = nil, isUnreadable: Bool = false) {
        self.tool = tool
        self.windows = windows
        self.updatedAt = updatedAt
        self.isUnreadable = isUnreadable
    }

    public var id: AITool {
        tool
    }

    public func peak(at date: Date) -> AIWindow? {
        windows.max { $0.used(at: date) < $1.used(at: date) }
    }
}

public struct AIUsageReading: Sendable, Equatable {
    /// Share of a limit that turns the module orange.
    public static let alertShare = 0.9

    /// Tools found on this Mac, in display order.
    public let tools: [AIToolUsage]
    public let readAt: Date

    public init(tools: [AIToolUsage], readAt: Date) {
        self.tools = tools
        self.readAt = readAt
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
}
