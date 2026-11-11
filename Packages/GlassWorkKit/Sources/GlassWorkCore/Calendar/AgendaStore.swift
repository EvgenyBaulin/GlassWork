import EventKit
import Foundation
import Observation

public enum DataAccess: Sendable, Equatable {
    case notAsked, granted, denied

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess, .authorized: self = .granted
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }
}

/// Calendar events and reminders. Access is requested only from an explicit button in a panel.
@MainActor
@Observable
public final class AgendaStore {
    public private(set) var eventsAccess: DataAccess
    public private(set) var remindersAccess: DataAccess
    public private(set) var events: [AgendaEvent] = []
    public private(set) var todos: [TodoItem] = []
    /// Every calendar on the Mac, shown or not.
    public private(set) var calendars: [CalendarChoice] = []

    @ObservationIgnored public var todoOptions = TodoOptions() {
        didSet {
            if todoOptions != oldValue, remindersAccess == .granted {
                loadReminders()
            }
        }
    }

    @ObservationIgnored public var calendarOptions = CalendarOptions() {
        didSet {
            if calendarOptions != oldValue, eventsAccess == .granted {
                loadEvents()
            }
        }
    }

    @ObservationIgnored private let store = EKEventStore()

    public init() {
        eventsAccess = DataAccess(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = DataAccess(EKEventStore.authorizationStatus(for: .reminder))
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    public func requestEventsAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        eventsAccess = DataAccess(EKEventStore.authorizationStatus(for: .event))
        refresh()
    }

    public func requestRemindersAccess() async {
        _ = try? await store.requestFullAccessToReminders()
        remindersAccess = DataAccess(EKEventStore.authorizationStatus(for: .reminder))
        refresh()
    }

    public func refresh() {
        if eventsAccess == .granted {
            loadEvents()
        }
        if remindersAccess == .granted {
            loadReminders()
        }
    }

    public func setCompleted(_ item: TodoItem, _ completed: Bool) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
        refresh()
    }

    public func addTodo(title: String) {
        guard let calendar = store.defaultCalendarForNewReminders() else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        try? store.save(reminder, commit: true)
        refresh()
    }

    private func loadEvents() {
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(86400 * 2)
        let all = store.calendars(for: .event)
        calendars = all.map(Self.calendarChoice).sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        let shown = all.filter { calendarOptions.shows(Self.calendarChoice($0)) }
        // An empty list would mean every calendar to EventKit, as nil does not.
        guard !shown.isEmpty else {
            events = []
            return
        }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: shown)
        events = store.events(matching: predicate).map(Self.agendaEvent).sorted { $0.start < $1.start }
    }

    private static func calendarChoice(_ calendar: EKCalendar) -> CalendarChoice {
        CalendarChoice(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            account: calendar.source?.title ?? "",
            color: hex(calendar.cgColor),
            isBirthdays: calendar.type == .birthday
        )
    }

    private static func agendaEvent(_ event: EKEvent) -> AgendaEvent {
        let declined = event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
        return AgendaEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isDeclined: declined,
            calendarColor: hex(event.calendar?.cgColor),
            location: event.location,
            callURL: event.url.flatMap { CallLink.find(in: [$0.absoluteString]) }
                ?? CallLink.find(in: [event.location, event.notes])
        )
    }

    private func loadReminders() {
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.todoItem)
            Task { @MainActor in self?.addCompleted(to: items) }
        }
    }

    /// The same access covers ticked reminders, so this asks for nothing new.
    private func addCompleted(to open: [TodoItem]) {
        guard let seconds = todoOptions.completed.seconds else {
            todos = todoOptions.arranged(open, now: Date())
            return
        }
        let predicate = store.predicateForCompletedReminders(
            withCompletionDateStarting: Date().addingTimeInterval(-seconds),
            ending: nil,
            calendars: nil
        )
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let done = (reminders ?? []).map(Self.todoItem)
            Task { @MainActor in
                guard let self else { return }
                self.todos = self.todoOptions.arranged(open + done, now: Date())
            }
        }
    }

    private nonisolated static func todoItem(_ reminder: EKReminder) -> TodoItem {
        TodoItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            listName: reminder.calendar?.title ?? "",
            listColor: hex(reminder.calendar?.cgColor),
            due: reminder.dueDateComponents?.date,
            isFlagged: reminder.priority == 1,
            isCompleted: reminder.isCompleted,
            completedAt: reminder.completionDate
        )
    }

    private nonisolated static func hex(_ color: CGColor?) -> String {
        guard let parts = color?.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        )?.components, parts.count >= 3 else { return "#3B82F6" }
        let values = parts.prefix(3).map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", values[0], values[1], values[2])
    }
}
