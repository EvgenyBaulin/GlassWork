import GlassWorkCore
import SwiftUI

/// The Reminders lists GlassWork shows, for the To-Dos page in Settings.
public struct TodoListSection: View {
    private let agenda: AgendaStore
    private let store: SettingsStore

    public init(agenda: AgendaStore, store: SettingsStore) {
        self.agenda = agenda
        self.store = store
    }

    private var options: TodoOptions {
        TodoOptions(options: store.settings.module(.todos)?.options ?? [:])
    }

    public var body: some View {
        TodoListChoices(
            access: agenda.remindersAccess,
            lists: agenda.reminderLists,
            options: options
        ) { list, isShown in
            let value = options.stored(after: list, isShown: isShown)
            store.update { $0.update(.todos) { $0.options[ItemOption.hiddenTodoLists] = value } }
        }
    }
}

struct TodoListChoices: View {
    let access: DataAccess
    let lists: [CalendarChoice]
    let options: TodoOptions
    let change: (CalendarChoice, Bool) -> Void

    var body: some View {
        Section(loc("Lists")) {
            if access == .granted {
                ForEach(lists) { row($0) }
            } else {
                Text(loc("Allow reminders access in the To-Dos panel to choose lists."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ list: CalendarChoice) -> some View {
        Toggle(isOn: Binding(get: { options.shows(list) }, set: { change(list, $0) })) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: list.color)).frame(width: 8, height: 8)
                Text(verbatim: list.title)
                Spacer()
                Text(verbatim: list.account).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}
