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
                if keepsLog {
                    await Self.recordCrashes(into: log)
                }
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

    private static let lastCrashReportKey = "diagnostics.lastCrashReport"

    /// macOS keeps its crash reports only for a while, so each new one becomes a line in the log, once.
    /// The line holds the exception and the app's own function, not the report's paths or machine details.
    private static func recordCrashes(into log: DiagnosticLog) async {
        let defaults = UserDefaults.standard
        let oldest = Date().addingTimeInterval(-TimeInterval(DiagnosticLog.keepDays) * 86400)
        let seen = (defaults.object(forKey: lastCrashReportKey) as? Date).map { max($0, oldest) } ?? oldest
        let reports = await Task.detached(priority: .utility) {
            CrashReportFolder.reports(after: seen).compactMap { report -> (CrashSummary, Date)? in
                guard let data = try? Data(contentsOf: report.url),
                      let crash = CrashReportParser.summary(of: data)
                else { return nil }
                return (crash, report.written)
            }
        }.value
        for (crash, written) in reports {
            await log.record(.crashed(crash))
            defaults.set(written, forKey: lastCrashReportKey)
        }
    }
}
