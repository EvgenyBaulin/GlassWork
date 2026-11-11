import GlassWorkCore
import SwiftUI

/// The calendars GlassWork shows, for the Calendar page in Settings.
public struct CalendarChoiceSection: View {
    private let agenda: AgendaStore
    private let store: SettingsStore

    public init(agenda: AgendaStore, store: SettingsStore) {
        self.agenda = agenda
        self.store = store
    }

    private var options: CalendarOptions {
        CalendarOptions(options: store.settings.module(.calendar)?.options ?? [:])
    }

    public var body: some View {
        CalendarChoiceList(
            access: agenda.eventsAccess,
            calendars: agenda.calendars,
            options: options
        ) { calendar, isShown in
            let value = options.stored(after: calendar, isShown: isShown, among: agenda.calendars)
            store.update { $0.update(.calendar) { $0.options[ItemOption.hiddenCalendars] = value } }
        }
    }
}

struct CalendarChoiceList: View {
    let access: DataAccess
    let calendars: [CalendarChoice]
    let options: CalendarOptions
    let change: (CalendarChoice, Bool) -> Void

    var body: some View {
        Section(loc("Calendars")) {
            if access == .granted {
                ForEach(calendars) { row($0) }
            } else {
                Text(loc("Allow calendar access in the Calendar panel to choose calendars."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ calendar: CalendarChoice) -> some View {
        Toggle(isOn: Binding(get: { options.shows(calendar) }, set: { change(calendar, $0) })) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: calendar.color)).frame(width: 8, height: 8)
                Text(verbatim: calendar.title)
                Spacer()
                Text(verbatim: calendar.account).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
