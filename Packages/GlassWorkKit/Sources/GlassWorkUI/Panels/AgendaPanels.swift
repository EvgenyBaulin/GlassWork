import GlassWorkCore
import SwiftUI

/// Shown until the user allows access; nothing is requested before this button is clicked.
struct AccessRequest: View {
    let title: String
    let access: DataAccess
    let request: () -> Void
    /// Opens the matching Privacy & Security page; shown only once access was denied.
    var openSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13)).multilineTextAlignment(.center)
            if access == .denied {
                Text(loc("Allow GlassWork in System Settings → Privacy & Security"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let openSettings {
                    Button(loc("Open Privacy Settings"), action: openSettings)
                }
            } else {
                Button(loc("Allow Access"), action: request)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }
}

/// The Privacy & Security pages the agenda panels send a denied user to.
enum AgendaPrivacy {
    static let calendars = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    static let reminders = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
}

struct AgendaRow: View {
    let event: AgendaEvent
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Color(hex: event.calendarColor)).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let url = event.callURL {
                // A link, because a plain button does nothing inside a system widget.
                Link(loc("Join"), destination: url).buttonStyle(.bordered).controlSize(.small)
            }
        }
    }
}

private func timeRange(_ event: AgendaEvent) -> String {
    guard !event.isAllDay else { return loc("All day") }
    let style = Date.FormatStyle(date: .omitted, time: .shortened).regional
    return "\(event.start.formatted(style)) – \(event.end.formatted(style))"
}

struct CalendarPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        let agenda = monitor.agenda
        let calendar = Calendar.current
        let today = agenda.events.filter { calendar.isDateInToday($0.start) && !$0.isDeclined }
        let tomorrow = agenda.events.first { calendar.isDateInTomorrow($0.start) && !$0.isDeclined }
        PanelFrame(
            module: .calendar,
            subtitle: Date().formatted(.dateTime.weekday(.wide).day().month()),
            footerTitle: loc("Open Calendar"),
            footerAction: { actions.openApp("com.apple.iCal") }
        ) {
            CalendarAgenda(
                access: agenda.eventsAccess,
                isLoaded: agenda.eventsLoaded,
                today: today,
                tomorrow: tomorrow,
                request: { Task { await agenda.requestEventsAccess() } },
                openSettings: { AgendaPrivacy.calendars.map(actions.openURL) }
            )
        }
    }
}

/// What the Calendar panel shows for each state of access and loading.
struct CalendarAgenda: View {
    let access: DataAccess
    let isLoaded: Bool
    let today: [AgendaEvent]
    let tomorrow: AgendaEvent?
    let request: () -> Void
    var openSettings: (() -> Void)?

    var body: some View {
        if access != .granted {
            AccessRequest(
                title: loc("See your events here"),
                access: access,
                request: request,
                openSettings: openSettings
            )
        } else if !isLoaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(loc("Loading…")).foregroundStyle(.secondary).font(.system(size: 12))
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            if today.isEmpty {
                Text(loc("No events today")).foregroundStyle(.secondary).font(.system(size: 12))
            }
            ForEach(today) { AgendaRow(event: $0, detail: timeRange($0)) }
            if let tomorrow {
                Divider()
                PanelSection(title: loc("Tomorrow")) {
                    AgendaRow(event: tomorrow, detail: timeRange(tomorrow))
                }
            }
        }
    }
}

struct EndsInPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    private var options: [String: String] {
        actions.moduleOptions(.endsIn)
    }

    var body: some View {
        let agenda = monitor.agenda
        let now = Date()
        let includeAllDay = options.flag(ItemOption.includesAllDay, default: false)
        let state = EndsInState(events: agenda.events, at: now, includeAllDay: includeAllDay)
        PanelFrame(module: .endsIn, subtitle: loc("\(state.current.count) now")) {
            if agenda.eventsAccess != .granted {
                AccessRequest(
                    title: loc("See your events here"),
                    access: agenda.eventsAccess,
                    request: { Task { await agenda.requestEventsAccess() } },
                    openSettings: { AgendaPrivacy.calendars.map(actions.openURL) }
                )
            } else if state.current.isEmpty {
                Text(freeText(state)).font(.system(size: 15, weight: .semibold))
                if let next = state.next {
                    AgendaRow(event: next, detail: timeRange(next))
                }
            } else {
                ForEach(state.current) { row($0, now: now) }
                if let next = state.next {
                    Divider()
                    PanelSection(title: loc("Next")) { AgendaRow(event: next, detail: timeRange(next)) }
                }
            }
        }
    }

    private func freeText(_ state: EndsInState) -> String {
        guard let next = state.next else { return loc("Free all day") }
        return loc("Free until \(next.start.timeText)")
    }

    private func row(_ event: AgendaEvent, now: Date) -> some View {
        let remaining = event.end.timeIntervalSince(now)
        let warnAt = TimeInterval(options.number(ItemOption.warnMinutes, default: 5) * 60)
        let tint: Color = switch EndsInUrgency(remaining: remaining, warnAt: warnAt) {
        case .normal: .primary
        case .soon: Palette.orange
        case .lastMinute: Palette.red
        }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                AgendaRow(event: event, detail: timeRange(event))
                Text(remaining.clockText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            ThinBar(value: event.progress(at: now), tint: Color(hex: event.calendarColor), height: 3)
        }
    }
}

struct TodosPanel: View {
    let monitor: SystemMonitor
    /// Nil until the user picks one, so the Settings choice applies until then.
    @State private var pickedFilter: TodoFilter?
    @State private var draft = ""
    @State private var undoItem: TodoItem?
    @Environment(\.panelActions) private var actions

    private var options: TodoOptions {
        TodoOptions(options: actions.moduleOptions(.todos))
    }

    var body: some View {
        let agenda = monitor.agenda
        let options = options
        let filter = pickedFilter ?? options.defaultFilter
        let items = filter.apply(to: agenda.todos, now: Date())
        PanelFrame(
            module: .todos,
            subtitle: loc("\(items.count) open"),
            footerTitle: loc("Open Reminders"),
            footerAction: { actions.openApp("com.apple.reminders") }
        ) {
            if agenda.remindersAccess == .granted {
                TodoFilterPicker(
                    filter: Binding(get: { filter }, set: { pickedFilter = $0 }),
                    counts: TodoFilter.counts(in: agenda.todos, now: Date())
                )
                if items.isEmpty {
                    AllClear()
                }
                ScrollView {
                    // Ticked items stay on the list for a while, so a slip can be undone.
                    let shown = items + (filter == .all ? agenda.todos.filter(\.isCompleted) : [])
                    VStack(alignment: .leading, spacing: 8) {
                        if options.groupsByList {
                            ForEach(TodoGroup.groups(of: shown)) { group in
                                TodoGroupHeader(name: group.name, color: group.color)
                                ForEach(group.items) { row($0, agenda: agenda) }
                            }
                        } else {
                            ForEach(shown) { row($0, agenda: agenda) }
                        }
                    }
                }
                .frame(maxHeight: 280)
                if let undoItem {
                    UndoToast(message: loc("Completed")) {
                        agenda.setCompleted(undoItem, false)
                        self.undoItem = nil
                    }
                    // Restarts for each new item, and stops by itself if the panel closes.
                    .task(id: undoItem.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if !Task.isCancelled {
                            self.undoItem = nil
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField(loc("Add a reminder"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            guard !draft.isEmpty else { return }
                            agenda.addTodo(title: draft, listID: destination(agenda, options))
                            draft = ""
                        }
                    destinationPicker(agenda, options)
                }
            } else {
                AccessRequest(
                    title: loc("See your reminders here"),
                    access: agenda.remindersAccess,
                    request: { Task { await agenda.requestRemindersAccess() } },
                    openSettings: { AgendaPrivacy.reminders.map(actions.openURL) }
                )
            }
        }
    }

    /// The remembered list while it still exists, and the Mac's own pick otherwise.
    private func destination(_ agenda: AgendaStore, _ options: TodoOptions) -> String? {
        let editable = agenda.reminderLists.filter(\.isEditable)
        if let remembered = options.newItemList, editable.contains(where: { $0.id == remembered }) {
            return remembered
        }
        return agenda.defaultListID
    }

    /// Where a new reminder goes. The choice is kept in the module's options.
    @ViewBuilder
    private func destinationPicker(_ agenda: AgendaStore, _ options: TodoOptions) -> some View {
        let lists = agenda.reminderLists.filter(\.isEditable)
        if lists.count > 1 {
            Picker(
                loc("Add to"),
                selection: Binding(
                    get: { destination(agenda, options) ?? "" },
                    set: { id in
                        actions.updateSettings { settings in
                            settings.update(.todos) { $0.options[ItemOption.todoNewItemList] = id }
                        }
                    }
                )
            ) {
                ForEach(lists) { Text(verbatim: $0.title).tag($0.id) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private func row(_ item: TodoItem, agenda: AgendaStore) -> some View {
        TodoRow(item: item) {
            agenda.setCompleted(item, !item.isCompleted)
            undoItem = item.isCompleted ? nil : item
        }
    }
}

/// The name of a Reminders list, in the list's colour, above its items.
struct TodoGroupHeader: View {
    let name: String
    let color: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: color)).frame(width: 7, height: 7)
            Text(verbatim: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

/// The four filters, each with how many reminders it holds.
struct TodoFilterPicker: View {
    @Binding var filter: TodoFilter
    let counts: [TodoFilter: Int]

    var body: some View {
        Picker("", selection: $filter) {
            Text(loc("All \(counts[.all] ?? 0)")).tag(TodoFilter.all)
            Text(loc("Today \(counts[.today] ?? 0)")).tag(TodoFilter.today)
            Text(loc("Overdue \(counts[.overdue] ?? 0)")).tag(TodoFilter.overdue)
            Text(loc("Flagged \(counts[.flagged] ?? 0)")).tag(TodoFilter.flagged)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

/// A short note under a list that offers to take the last action back.
struct UndoToast: View {
    let message: String
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
            Text(message).font(.system(size: 12))
            Spacer()
            Button(loc("Undo"), action: undo).buttonStyle(.link).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Shown when no reminder is open.
struct AllClear: View {
    var body: some View {
        PanelMessage(symbol: "checkmark.circle", title: loc("All clear"), tint: Palette.green)
    }
}

/// One reminder. Clicking the circle ticks it, or takes the tick back.
struct TodoRow: View {
    let item: TodoItem
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color(hex: item.listColor))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                if let due = item.due, !item.isCompleted {
                    Text(due.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(due < Date() ? Palette.red : .secondary)
                }
            }
            Spacer()
            if item.level != .none, !item.isCompleted {
                Text(verbatim: item.level.marks)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.level == .high ? Palette.orange : .secondary)
            }
        }
    }
}
