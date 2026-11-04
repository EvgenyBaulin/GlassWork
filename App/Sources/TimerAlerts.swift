import AppKit
import GlassWorkCore
import GlassWorkUI
import UserNotifications

/// What the app does when a timer reaches zero.
extension AppModel {
    func timerFinished(_ timer: CountdownTimer) {
        let alert = TimerAlert(options: store.settings.module(.timers)?.options ?? [:])
        if let name = alert.soundName {
            NSSound(named: NSSound.Name(name))?.play()
        }
        if alert.notifies {
            Task { await Self.notifyIfAllowed(title: loc("Timer finished"), body: timer.title) }
        }
    }

    /// Asking for permission is left to the switch in General: a timer must not raise the system's question.
    private static func notifyIfAllowed(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
