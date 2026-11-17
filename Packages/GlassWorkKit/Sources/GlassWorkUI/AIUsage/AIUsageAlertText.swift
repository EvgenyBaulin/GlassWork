import Foundation
import GlassWorkCore

/// What a limit notification says.
public enum AIUsageAlertText {
    /// "Codex at 85% of the 5-hour limit", and below it when the limit resets.
    public static func make(_ alert: AIUsageAlert, now: Date) -> (title: String, body: String) {
        let tool = alert.tool.title
        let percent = Format.percent(alert.used)
        let title = switch alert.kind {
        case .fiveHour: loc("\(tool) at \(percent) of the 5-hour limit")
        case .week: loc("\(tool) at \(percent) of the weekly limit")
        case .month: loc("\(tool) at \(percent) of the monthly limit")
        }
        guard let reset = alert.resetsAt, reset > now else { return (title, "") }
        let when = alert.kind == .fiveHour
            ? reset.timeText
            : AIWindowText.resetDay(reset, from: now)
        return (title, loc("Resets \(when)"))
    }
}
