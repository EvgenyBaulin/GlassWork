import GlassWorkCore
import SwiftUI

public extension Permission {
    var title: String {
        switch self {
        case .calendars: loc("Calendars")
        case .reminders: loc("Reminders")
        case .location: loc("Location")
        case .screenRecording: loc("Screen Recording")
        case .accessibility: loc("Accessibility")
        case .notifications: loc("Notifications")
        case .fullDiskAccess: loc("Full Disk Access")
        case .photos: loc("Photos")
        case .contacts: loc("Contacts")
        }
    }

    var purpose: String {
        switch self {
        case .calendars: loc("Events in Calendar, Ends In and the agenda")
        case .reminders: loc("The To-Do list")
        case .location: loc("Weather for where you are")
        case .screenRecording: loc("Text Capture reads text from the screen")
        case .accessibility: loc("Paste on click and Window Tiles")
        case .notifications: loc("Alerts, timers, usage limits and outages")
        case .fullDiskAccess: loc("Time Machine backup history")
        case .photos: loc("On This Day")
        case .contacts: loc("Birthdays")
        }
    }

    var symbol: String {
        switch self {
        case .calendars: "calendar"
        case .reminders: "checklist"
        case .location: "location"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .notifications: "bell.badge"
        case .fullDiskAccess: "externaldrive"
        case .photos: "photo"
        case .contacts: "person.crop.circle"
        }
    }
}

/// One permission and where it stands.
public struct PermissionRowModel: Identifiable, Equatable, Sendable {
    public let permission: Permission
    public let state: PermissionState

    public var id: String {
        permission.id
    }

    public init(permission: Permission, state: PermissionState) {
        self.permission = permission
        self.state = state
    }
}

/// A permission with its state and a button to the right pane of System Settings.
public struct PermissionRow: View {
    private let model: PermissionRowModel
    private let open: () -> Void

    public init(_ model: PermissionRowModel, open: @escaping () -> Void) {
        self.model = model
        self.open = open
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.permission.symbol)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.permission.title)
                Text(model.permission.purpose).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(stateText, systemImage: stateSymbol)
                .foregroundStyle(stateColor)
                .font(.callout)
            Button(model.state == .granted ? loc("Open Settings") : loc("Allow…"), action: open)
                .disabled(model.state == .notNeeded)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateText: String {
        switch model.state {
        case .granted: loc("Granted")
        case .notGranted: loc("Not granted")
        case .notNeeded: loc("Not needed")
        }
    }

    private var stateSymbol: String {
        switch model.state {
        case .granted: "checkmark.circle.fill"
        case .notGranted: "exclamationmark.circle.fill"
        case .notNeeded: "minus.circle"
        }
    }

    private var stateColor: Color {
        switch model.state {
        case .granted: .green
        case .notGranted: .orange
        case .notNeeded: .secondary
        }
    }
}

/// The Permissions page: every permission the app may use, most pressing first.
public struct PermissionsPaneView: View {
    private let rows: [PermissionRowModel]
    private let open: (Permission) -> Void

    public init(rows: [PermissionRowModel], open: @escaping (Permission) -> Void) {
        self.rows = rows
        self.open = open
    }

    public var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    PermissionRow(row) { open(row.permission) }
                }
            } footer: {
                Text(loc("Not needed means no enabled module uses it. The list updates when you return from Settings."))
            }
        }
        .formStyle(.grouped)
    }
}
