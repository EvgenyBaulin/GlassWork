import GlassWorkCore
import SwiftUI

/// Shown until the user allows access; nothing is requested before this button is clicked.
struct AccessRequest: View {
    let title: String
    let access: DataAccess
    let request: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 13)).multilineTextAlignment(.center)
            if access == .denied {
                Text(loc("Allow GlassWork in System Settings → Privacy & Security"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button(loc("Allow Access"), action: request)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }
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
    let style = Date.FormatStyle(date: .omitted, time: .shortened)
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
            if agenda.eventsAccess == .granted {
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
            } else {
                AccessRequest(title: loc("See your events here"), access: agenda.eventsAccess) {
                    Task { await agenda.requestEventsAccess() }
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
                AccessRequest(title: loc("See your events here"), access: agenda.eventsAccess) {
                    Task { await agenda.requestEventsAccess() }
                }
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
        return loc("Free until \(next.start.formatted(date: .omitted, time: .shortened))")
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
    @State private var filter = TodoFilter.all
    @State private var draft = ""
    @Environment(\.panelActions) private var actions

    var body: some View {
        let agenda = monitor.agenda
        let items = filter.apply(to: agenda.todos, now: Date())
        PanelFrame(
            module: .todos,
            subtitle: loc("\(items.count) open"),
            footerTitle: loc("Open Reminders"),
            footerAction: { actions.openApp("com.apple.reminders") }
        ) {
            if agenda.remindersAccess == .granted {
                Picker("", selection: $filter) {
                    Text(loc("All")).tag(TodoFilter.all)
                    Text(loc("Today")).tag(TodoFilter.today)
                    Text(loc("Overdue")).tag(TodoFilter.overdue)
                    Text(loc("Flagged")).tag(TodoFilter.flagged)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { row($0, agenda: agenda) }
                    }
                }
                .frame(maxHeight: 280)
                TextField(loc("Add a reminder"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard !draft.isEmpty else { return }
                        agenda.addTodo(title: draft)
                        draft = ""
                    }
            } else {
                AccessRequest(title: loc("See your reminders here"), access: agenda.remindersAccess) {
                    Task { await agenda.requestRemindersAccess() }
                }
            }
        }
    }

    private func row(_ item: TodoItem, agenda: AgendaStore) -> some View {
        HStack(spacing: 8) {
            Button {
                agenda.setCompleted(item, true)
            } label: {
                Image(systemName: "circle").foregroundStyle(Color(hex: item.listColor))
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13)).lineLimit(2)
                if let due = item.due {
                    Text(due.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(due < Date() ? Palette.red : .secondary)
                }
            }
            Spacer()
            if item.isFlagged {
                Image(systemName: "flag.fill").foregroundStyle(Palette.orange).font(.system(size: 10))
            }
        }
    }
}
