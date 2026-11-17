import Foundation

/// A macOS permission the app may ask for.
public enum Permission: String, CaseIterable, Sendable, Identifiable {
    case calendars, reminders, location, screenRecording, accessibility, notifications
    case fullDiskAccess, photos, contacts

    public var id: String {
        rawValue
    }

    /// The pane of System Settings where the user changes it.
    public var settingsURL: URL {
        let privacy = "x-apple.systempreferences:com.apple.preference.security?"
        let address = switch self {
        case .calendars: privacy + "Privacy_Calendars"
        case .reminders: privacy + "Privacy_Reminders"
        case .location: privacy + "Privacy_LocationServices"
        case .screenRecording: privacy + "Privacy_ScreenCapture"
        case .accessibility: privacy + "Privacy_Accessibility"
        case .fullDiskAccess: privacy + "Privacy_AllFiles"
        case .photos: privacy + "Privacy_Photos"
        case .contacts: privacy + "Privacy_Contacts"
        case .notifications: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        }
        // The addresses are literals above, so this cannot fail.
        return URL(string: address) ?? URL(fileURLWithPath: "/System/Applications/System Settings.app")
    }
}

public enum PermissionState: Sendable, Equatable {
    case granted
    /// Something enabled needs it and macOS has not allowed it.
    case notGranted
    /// Nothing enabled needs it.
    case notNeeded
}

public enum PermissionNeeds {
    /// What `state` reports for a permission: a granted one stays granted, even when nothing needs it now.
    public static func state(isNeeded: Bool, isGranted: Bool) -> PermissionState {
        if isGranted {
            .granted
        } else {
            isNeeded ? .notGranted : .notNeeded
        }
    }

    /// A module needs its permissions as soon as it is not off, including in the Hub only.
    public static func permissions(of module: ModuleID, in settings: AppSettings) -> Set<Permission> {
        guard let setting = settings.module(module), setting.mode != .off else { return [] }
        switch module {
        case .calendar, .endsIn: return [.calendars]
        case .todos: return [.reminders]
        case .timers, .ping, .aiUsage: return [.notifications]
        case .weather: return settings.weather.useCurrentLocation ? [.location] : []
        default: return []
        }
    }

    /// Everything the enabled modules and options need. Full Disk Access is only known to be needed once
    /// a reader has run into it, such as the Time Machine widget, so the caller says so.
    public static func needed(in settings: AppSettings, needsFullDiskAccess: Bool = false) -> Set<Permission> {
        var result = Set(ModuleID.allCases.flatMap { permissions(of: $0, in: settings) })
        if settings.alerts.isEnabled {
            result.insert(.notifications)
        }
        if settings.clipboard.pasteOnClick || settings.windowTiles.isEnabled {
            result.insert(.accessibility)
        }
        if settings.shortcuts.shortcut(for: .textCapture) != nil {
            result.insert(.screenRecording)
        }
        if needsFullDiskAccess {
            result.insert(.fullDiskAccess)
        }
        if settings.personalWidgets.isOnThisDayOn {
            result.insert(.photos)
        }
        if settings.personalWidgets.isBirthdaysOn {
            result.insert(.contacts)
        }
        return result
    }

    /// Needs of these modules only, for the choices made while setting the app up.
    public static func needed(byModules modules: [ModuleID], in settings: AppSettings) -> Set<Permission> {
        var chosen = settings
        for id in ModuleID.allCases where !modules.contains(id) {
            chosen.update(id) { $0.mode = .off }
        }
        return Set(modules.flatMap { permissions(of: $0, in: chosen) })
    }
}

/// Whether a protected file can be opened, which only Full Disk Access allows.
public enum FullDiskAccessProbe {
    /// The file macOS keeps privacy decisions in. It always exists, and only an app with access can open it.
    public static var path: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.apple.TCC/TCC.db").path(percentEncoded: false)
    }

    /// `open` returns what opening the path gave: 0 for success, or the error number.
    public static func isGranted(open: (String) -> Int32) -> Bool {
        open(path) == 0
    }
}
