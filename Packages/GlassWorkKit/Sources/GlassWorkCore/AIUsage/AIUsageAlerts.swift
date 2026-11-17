import Foundation

/// A tool's window that has just reached the module's warning level.
public struct AIUsageAlert: Sendable, Equatable {
    public let tool: AITool
    public let kind: AIWindow.Kind
    /// Share of the limit used, from 0 to 1.
    public let used: Double
    public let resetsAt: Date?

    /// One notification per tool and window, so a newer one replaces the older.
    public var identifier: String {
        "aiUsage.\(tool.rawValue).\(kind)"
    }
}

/// Decides when a limit notification fires: once per window per reset period.
public struct AIUsageAlertTracker: Sendable {
    private struct Key: Hashable {
        let tool: AITool
        let kind: AIWindow.Kind
    }

    /// Reset times of one window that differ by less than this are the same period; tools word them loosely.
    private static let sameResetWithin: TimeInterval = 1800

    /// The reset time of the period already announced, per window.
    private var announced: [Key: Date?] = [:]

    public init() {}

    /// Returns the windows that just reached `warnShare`. A window announced already stays quiet until its
    /// limit resets, even when it dips below the level and comes back.
    public mutating func update(_ reading: AIUsageReading, warnShare: Double, now: Date) -> [AIUsageAlert] {
        var fired: [AIUsageAlert] = []
        for usage in reading.tools {
            for window in usage.windows {
                let key = Key(tool: usage.tool, kind: window.kind)
                let used = window.used(at: now)
                let isOver = used >= warnShare
                if let period = announced[key] {
                    if Self.isSamePeriod(period, window.resetsAt) {
                        // Without a reset time the only sign of a new period is the value falling back.
                        if window.resetsAt == nil, !isOver {
                            announced[key] = nil
                        }
                        continue
                    }
                    announced[key] = nil
                }
                if isOver {
                    announced[key] = .some(window.resetsAt)
                    fired.append(AIUsageAlert(
                        tool: usage.tool,
                        kind: window.kind,
                        used: used,
                        resetsAt: window.resetsAt
                    ))
                }
            }
        }
        return fired
    }

    private static func isSamePeriod(_ old: Date?, _ new: Date?) -> Bool {
        switch (old, new) {
        case (nil, nil): true
        case let (old?, new?): abs(old.timeIntervalSince(new)) < sameResetWithin
        default: false
        }
    }
}

public extension AIUsageOption {
    /// "Notify at warning": one notification when a limit reaches the warning level.
    static let notifyAtWarning = "notifyAtWarn"

    static func notifies(_ options: [String: String]) -> Bool {
        options.flag(notifyAtWarning, default: true)
    }
}
