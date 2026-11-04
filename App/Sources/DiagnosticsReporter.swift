import Foundation
import GlassWorkCore

/// Tells the diagnostic log what happened. The log hears only about these things, and nothing at all until the
/// user turns it on.
@MainActor
final class DiagnosticsReporter {
    private let log = DiagnosticLog()
    private var isLogging = false
    private var hasReportedSettingsProblem = false

    /// Runs on every settings change, so each part only acts when something really changed.
    func apply(keepsLog: Bool, hasSettingsProblem: Bool) {
        if keepsLog != isLogging {
            isLogging = keepsLog
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
            Task { [log] in
                await log.setEnabled(keepsLog)
                await log.record(.logStarted(version: version))
            }
        }
        if hasSettingsProblem, !hasReportedSettingsProblem {
            record(.settingsProblem)
        }
        hasReportedSettingsProblem = hasSettingsProblem
    }

    func record(_ event: DiagnosticEvent) {
        Task { [log] in await log.record(event) }
    }
}
