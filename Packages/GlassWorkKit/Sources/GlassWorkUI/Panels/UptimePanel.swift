import GlassWorkCore
import SwiftUI

struct UptimePanel: View {
    let monitor: SystemMonitor

    var body: some View {
        UptimePanelContent(boot: SystemClock.bootTime() ?? .now, history: monitor.sleeps.history, now: .now)
    }
}

/// Uptime with the last sleep and wake, the sleep count and the latest awake sessions.
struct UptimePanelContent: View {
    let boot: Date
    let history: SleepHistory
    let now: Date
    private static let shownSessions = 5

    var body: some View {
        PanelFrame(module: .uptime, subtitle: "") {
            BigFigure(text: CompactDuration.format(now.timeIntervalSince(boot)))
            InfoRow(title: loc("Started"), value: boot.formatted(date: .abbreviated, time: .shortened))
            InfoRow(title: loc("Last sleep"), value: stamp(history.lastSleep))
            InfoRow(title: loc("Last wake"), value: stamp(history.lastWake))
            InfoRow(title: loc("Sleeps since start"), value: "\(history.sleepCount)")
            let sessions = history.sessions(limit: Self.shownSessions)
            if !sessions.isEmpty {
                Divider()
                Text(loc("Awake sessions"))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sessions) { session in
                    InfoRow(title: range(session), value: CompactDuration.format(session.duration(now: now)))
                }
            }
        }
    }

    private func stamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func range(_ session: AwakeSession) -> String {
        let start = session.start.formatted(date: .omitted, time: .shortened)
        let end = session.end.map { $0.formatted(date: .omitted, time: .shortened) } ?? loc("now")
        return "\(start) – \(end)"
    }
}
