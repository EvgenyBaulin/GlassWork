import Foundation
@testable import GlassWorkCore
import Testing

struct PermissionsTests {
    private func settings(_ change: (inout AppSettings) -> Void = { _ in }) -> AppSettings {
        var settings = AppSettings()
        change(&settings)
        return settings
    }

    @Test func stateGrantedWinsOverNeed() {
        #expect(PermissionNeeds.state(isNeeded: true, isGranted: true) == .granted)
        #expect(PermissionNeeds.state(isNeeded: false, isGranted: true) == .granted)
        #expect(PermissionNeeds.state(isNeeded: true, isGranted: false) == .notGranted)
        #expect(PermissionNeeds.state(isNeeded: false, isGranted: false) == .notNeeded)
    }

    @Test func aModuleNeedsItsPermissionUnlessOff() {
        var calendarOn = settings { $0.update(.calendar) { $0.mode = .hubOnly } }
        #expect(PermissionNeeds.needed(in: calendarOn).contains(.calendars))
        calendarOn.update(.calendar) { $0.mode = .off }
        calendarOn.update(.endsIn) { $0.mode = .off }
        #expect(PermissionNeeds.needed(in: calendarOn).contains(.calendars) == false)
        let endsIn = settings { $0.update(.endsIn) { $0.mode = .menuBar } }
        #expect(PermissionNeeds.needed(in: endsIn).contains(.calendars))
        let todos = settings { $0.update(.todos) { $0.mode = .hubOnly } }
        #expect(PermissionNeeds.needed(in: todos).contains(.reminders))
    }

    @Test func weatherNeedsLocationOnlyForTheCurrentPlace() {
        var weather = settings { $0.update(.weather) { $0.mode = .hubOnly } }
        #expect(PermissionNeeds.needed(in: weather).contains(.location) == false)
        weather.weather.useCurrentLocation = true
        #expect(PermissionNeeds.needed(in: weather).contains(.location))
    }

    @Test func optionsDecideAccessibilityAndNotifications() {
        #expect(PermissionNeeds.needed(in: settings { $0.clipboard.pasteOnClick = true }).contains(.accessibility))
        #expect(PermissionNeeds.needed(in: settings { $0.windowTiles.isEnabled = true }).contains(.accessibility))
        #expect(PermissionNeeds.needed(in: settings { $0.alerts.isEnabled = true }).contains(.notifications))
        let timers = settings { $0.update(.timers) { $0.mode = .hubOnly } }
        #expect(PermissionNeeds.needed(in: timers).contains(.notifications))
    }

    @Test func screenRecordingFollowsTheTextCaptureShortcut() {
        #expect(PermissionNeeds.needed(in: settings()).contains(.screenRecording))
        let cleared = settings { $0.shortcuts.set(.textCapture, to: nil) }
        #expect(PermissionNeeds.needed(in: cleared).contains(.screenRecording) == false)
    }

    @Test func fullDiskAccessAndPersonalDataAreAskedFor() {
        #expect(PermissionNeeds.needed(in: settings()).contains(.fullDiskAccess) == false)
        #expect(PermissionNeeds.needed(in: settings(), needsFullDiskAccess: true).contains(.fullDiskAccess))
        #expect(PermissionNeeds.needed(in: settings { $0.personalWidgets.isOnThisDayOn = true }).contains(.photos))
        #expect(PermissionNeeds.needed(in: settings { $0.personalWidgets.isBirthdaysOn = true }).contains(.contacts))
    }

    @Test func theDefaultModulesNeedOnlyWhatTheHubOnesAsk() {
        let needed = PermissionNeeds.needed(in: settings { $0.shortcuts.set(.textCapture, to: nil) })
        // Hub-only modules count as on: Calendar and Ends In, To-Do, Timers.
        #expect(needed == [.calendars, .reminders, .notifications])
    }

    @Test func everyPermissionHasASettingsLink() {
        for permission in Permission.allCases {
            #expect(permission.settingsURL.scheme == "x-apple.systempreferences")
        }
        #expect(Permission.screenRecording.settingsURL.absoluteString.hasSuffix("Privacy_ScreenCapture"))
        #expect(Permission.accessibility.settingsURL.absoluteString.hasSuffix("Privacy_Accessibility"))
        #expect(Permission.notifications.settingsURL.absoluteString.contains("Notifications"))
    }

    @Test func fullDiskAccessProbeReadsTheErrorNumber() {
        #expect(FullDiskAccessProbe.isGranted { _ in 0 })
        #expect(FullDiskAccessProbe.isGranted { _ in EPERM } == false)
        #expect(FullDiskAccessProbe.path.hasSuffix("com.apple.TCC/TCC.db"))
    }
}
