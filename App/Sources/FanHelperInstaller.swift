import AppKit
import GlassWorkCore
import ServiceManagement
import UserNotifications

/// Registers the helper with launchd. Reading the status is free; `install` runs only from a button.
@MainActor
final class FanHelperInstaller: FanHelperInstalling {
    private var service: SMAppService {
        .daemon(plistName: FanHelperIdentity.plistName)
    }

    var state: FanHelperState {
        switch service.status {
        case .enabled: .installed
        case .requiresApproval: .needsApproval
        case .notRegistered, .notFound: .notInstalled
        @unknown default: .notInstalled
        }
    }

    func install() throws {
        try service.register()
    }

    func uninstall() async throws {
        try await service.unregister()
    }

    func openApproval() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func connect(onLost: @escaping @Sendable () -> Void) -> FanHelperClient? {
        FanHelperConnection.privileged(onLost: onLost)
    }
}

/// Tells the user about the failsafe. Permission is never asked for here: without it, the panel
/// banner is the only notice.
enum FanNotifications {
    static func failsafe(celsius _: Double, title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: "fans.failsafe", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}
