import Foundation
@testable import GlassWorkCore

extension DataSamples {
    static var github: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        func pull(
            _ title: String,
            _ number: Int,
            minutes: Double,
            added: Int,
            removed: Int,
            review: PullRequestSummary.Review = .none,
            passed: Int = 0,
            failed: Int = 0,
            running: Int = 0
        ) -> PullRequestSummary {
            PullRequestSummary(
                title: title,
                repository: "evgeny/glasswork",
                number: number,
                url: "https://github.com/evgeny/glasswork/pull/\(number)",
                updatedAt: sampleNow.addingTimeInterval(-minutes * 60),
                additions: added,
                deletions: removed,
                review: review,
                checksPassed: passed,
                checksFailed: failed,
                checksRunning: running
            )
        }
        snapshot.github = WidgetGitHub(
            requested: [
                pull("Glass cards for the dashboard", 142, minutes: 12, added: 412, removed: 88),
                pull("Retry uploads when the network drops", 88, minutes: 60, added: 96, removed: 14),
            ],
            mine: [
                pull("Stream the activity feed", 145, minutes: 7, added: 10, removed: 2, passed: 4, running: 2),
                pull("JSON file watcher", 141, minutes: 120, added: 1, removed: 2, review: .approved, passed: 6),
                pull("Add /health endpoint", 91, minutes: 300, added: 10, removed: 2, passed: 5, failed: 1),
                pull("Widget sizes", 137, minutes: 1440, added: 3, removed: 1, review: .changesRequested, passed: 6),
            ],
            updatedAt: sampleNow.addingTimeInterval(-60)
        )
        return snapshot
    }

    static var today: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.battery = BatterySample(
            charge: 0.82, isCharging: true, isOnAC: true, minutesRemaining: 65,
            health: 0.91, cycleCount: 312, temperature: 31, adapterWatts: 96
        )
        func event(_ title: String, hours: Double, minutes: Double, color: String, call: Bool = false) -> AgendaEvent {
            AgendaEvent(
                id: title,
                title: title,
                start: sampleNow.addingTimeInterval(hours * 3600),
                end: sampleNow.addingTimeInterval(hours * 3600 + minutes * 60),
                calendarColor: color,
                callURL: call ? URL(string: "https://example.com/call") : nil
            )
        }
        snapshot.events = [
            event("Yoga", hours: 2.15, minutes: 60, color: "#5AC8FA"),
            event("Call with Anna", hours: 3.4, minutes: 30, color: "#AF52DE", call: true),
            event("Evening walk", hours: 5, minutes: 45, color: "#34C759"),
            event("Standup", hours: 24, minutes: 15, color: "#3B82F6", call: true),
            event("Dentist", hours: 26, minutes: 60, color: "#FF9500"),
        ]
        return snapshot
    }
}
