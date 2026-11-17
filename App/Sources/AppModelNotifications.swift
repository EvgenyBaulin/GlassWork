import Foundation
import GlassWorkCore
import GlassWorkUI

/// Notifications from modules, each on the module's own switch.
extension AppModel {
    func checkUsageAndPing() {
        let developer = monitor.developer
        let usage = store.settings.module(.aiUsage)
        if usage?.mode != .off, AIUsageOption.notifies(usage?.options ?? [:]), let reading = developer.aiUsage {
            let now = Date()
            for alert in usageAlerts.update(reading, warnShare: reading.warnLevel, now: now) {
                let text = AIUsageAlertText.make(alert, now: now)
                Task { await Self.notifyIfAllowed(title: text.title, body: text.body, identifier: alert.identifier) }
            }
        }
        if store.settings.module(.ping)?.mode != .off, let sample = developer.ping.latest {
            let host = developer.options.pingHost
            let event = pingOutages.update(host: host, outcome: sample.outcome, at: sample.date)
            switch event {
            case let .down(host):
                Task { await Self.notifyIfAllowed(
                    title: loc("\(host) is unreachable"),
                    body: "",
                    identifier: "ping.\(host)"
                ) }
            case let .recovered(host, downFor):
                let title = loc("\(host) is back (down for \(CompactDuration.format(downFor)))")
                Task { await Self.notifyIfAllowed(title: title, body: "", identifier: "ping.\(host)") }
            case nil:
                break
            }
        }
    }
}
