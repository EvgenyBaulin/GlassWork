import AppKit
import ApplicationServices
import CoreLocation
import EventKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI
import UserNotifications

/// Reads what macOS allows, without ever asking: every call here only looks.
@MainActor
enum PermissionReader {
    static func granted() async -> Set<Permission> {
        var result = Set<Permission>()
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            result.insert(.calendars)
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            result.insert(.reminders)
        }
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorized: result.insert(.location)
        default: break
        }
        if CGPreflightScreenCaptureAccess() {
            result.insert(.screenRecording)
        }
        if AXIsProcessTrusted() {
            result.insert(.accessibility)
        }
        let notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if notifications == .authorized || notifications == .provisional {
            result.insert(.notifications)
        }
        if FullDiskAccessProbe.isGranted(open: Self.openForReading) {
            result.insert(.fullDiskAccess)
        }
        if SystemPhotoLibrary().access() == .granted {
            result.insert(.photos)
        }
        if SystemBirthdays().access() == .granted {
            result.insert(.contacts)
        }
        return result
    }

    /// Opens and closes the file. Only opening it tells whether macOS lets this app in.
    private static func openForReading(_ path: String) -> Int32 {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { return errno }
        close(descriptor)
        return 0
    }

    static func openSettings(_ permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}

struct PermissionsPane: View {
    let store: SettingsStore
    let monitor: SystemMonitor
    @State private var granted: Set<Permission> = []

    var body: some View {
        PermissionsPaneView(rows: rows, open: PermissionReader.openSettings)
            .task { granted = await PermissionReader.granted() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task { granted = await PermissionReader.granted() }
            }
    }

    private var rows: [PermissionRowModel] {
        let needed = PermissionNeeds.needed(
            in: store.settings,
            needsFullDiskAccess: monitor.timeMachine?.state == .needsPermission
        )
        return Permission.allCases.map { permission in
            PermissionRowModel(
                permission: permission,
                state: PermissionNeeds.state(
                    isNeeded: needed.contains(permission),
                    isGranted: granted.contains(permission)
                )
            )
        }
    }
}
