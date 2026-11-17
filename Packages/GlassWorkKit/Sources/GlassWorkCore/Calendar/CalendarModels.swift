import Foundation

/// A calendar event reduced to what the modules show.
public struct AgendaEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var isDeclined: Bool
    public var calendarColor: String
    public var location: String?
    public var callURL: URL?

    public init(
        id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, isDeclined: Bool = false,
        calendarColor: String = "#3B82F6", location: String? = nil, callURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isDeclined = isDeclined
        self.calendarColor = calendarColor
        self.location = location
        self.callURL = callURL
    }

    public func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(start) / total, 0), 1)
    }
}

/// How urgent an event's remaining time looks.
public enum EndsInUrgency: Sendable, Equatable {
    case normal, soon, lastMinute

    public init(remaining: TimeInterval, warnAt: TimeInterval = 300) {
        switch remaining {
        case ...60: self = .lastMinute
        case ...warnAt: self = .soon
        default: self = .normal
        }
    }
}

/// What is happening right now, for the Ends In module and widget.
public struct EndsInState: Sendable, Equatable {
    /// Events in progress, the one ending soonest first.
    public var current: [AgendaEvent]
    public var next: AgendaEvent?

    public init(events: [AgendaEvent], at date: Date, includeAllDay: Bool = false) {
        let usable = events.filter { !$0.isDeclined && (includeAllDay || !$0.isAllDay) }
        current = usable.filter { $0.start <= date && date < $0.end }.sorted { $0.end < $1.end }
        next = usable.filter { $0.start > date }.min { $0.start < $1.start }
    }

    /// Moments when the stack changes, used to schedule widget timelines.
    public static func changeDates(of events: [AgendaEvent], after date: Date) -> [Date] {
        Array(Set(events.flatMap { [$0.start, $0.end] }.filter { $0 > date })).sorted()
    }
}

/// Finds the meeting link in an event's text fields.
public enum CallLink {
    private static let hosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "telemost.yandex.ru",
        "facetime.apple.com",
    ]

    public static func find(in texts: [String?]) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in texts.compactMap(\.self) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                if let url = match.url, isCall(url) {
                    return url
                }
            }
        }
        return nil
    }

    /// Invitations come from other people, so a link opens only over the web and only on a known
    /// service: `evilzoom.us` or a custom scheme pointing at `zoom.us` does not pass.
    static func isCall(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// A reminder from the Reminders app.
public struct TodoItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var listName: String
    public var listColor: String
    public var due: Date?
    /// EventKit has no public flag, so this means "high priority" and nothing else.
    public var isFlagged: Bool
    public var isCompleted: Bool
    public var completedAt: Date?
    /// Reminders' own scale: 1–4 high, 5 medium, 6–9 low. Nil for none, and in snapshots from earlier versions.
    public var priority: Int?

    public init(
        id: String, title: String, listName: String, listColor: String = "#3B82F6",
        due: Date? = nil, isFlagged: Bool = false, isCompleted: Bool = false, completedAt: Date? = nil,
        priority: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.listName = listName
        self.listColor = listColor
        self.due = due
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.priority = priority
    }

    /// The priority as a level. An item that is flagged and has no priority of its own counts as high.
    public var level: TodoPriority {
        priority.map(TodoPriority.init(reminders:)) ?? (isFlagged ? .high : .none)
    }
}

/// How urgent a reminder is, from the priority the Reminders app stores.
public enum TodoPriority: Int, Sendable, Comparable {
    case none, low, medium, high

    public init(reminders value: Int) {
        switch value {
        case 1 ... 4: self = .high
        case 5: self = .medium
        case 6 ... 9: self = .low
        default: self = .none
        }
    }

    public static func < (left: Self, right: Self) -> Bool {
        left.rawValue < right.rawValue
    }

    /// `!!!`, `!!` or `!`, as Reminders writes them. Empty for none.
    public var marks: String {
        String(repeating: "!", count: rawValue)
    }
}

/// Reminders of one list, for a panel that groups by list.
public struct TodoGroup: Identifiable, Sendable, Equatable {
    public var name: String
    public var color: String
    public var items: [TodoItem]
    public var id: String {
        name
    }

    /// Lists in the order they first appear, and each list keeps its items' order.
    public static func groups(of items: [TodoItem]) -> [TodoGroup] {
        var result: [TodoGroup] = []
        for item in items {
            if let index = result.firstIndex(where: { $0.name == item.listName }) {
                result[index].items.append(item)
            } else {
                result.append(TodoGroup(name: item.listName, color: item.listColor, items: [item]))
            }
        }
        return result
    }
}

public enum TodoSort: String, Sendable, CaseIterable {
    /// The order the Reminders app keeps.
    case manual
    case dueDate, title
}

/// How long a ticked item stays on the list.
public enum CompletedTodos: String, Sendable, CaseIterable {
    case hide, day, week

    public var seconds: TimeInterval? {
        switch self {
        case .hide: nil
        case .day: 86400
        case .week: 7 * 86400
        }
    }
}

/// The order of the to-do list, which the panel and the widgets share.
public struct TodoOptions: Sendable, Equatable {
    public var sort = TodoSort.manual
    public var completed = CompletedTodos.hide
    public var groupsByList = true
    public var defaultFilter = TodoFilter.all
    /// The list new reminders go to, remembered from the panel. Nil or a missing list means the Mac's default.
    public var newItemList: String?
    /// Nil until the first choice: every list shows.
    private var hidden: Set<String>?

    public init() {}

    public init(options: [String: String]) {
        sort = options.choice(ItemOption.todoSort, default: .manual)
        completed = options.choice(ItemOption.todoCompleted, default: .hide)
        groupsByList = options.flag(ItemOption.todoGroupsByList, default: true)
        defaultFilter = options.choice(ItemOption.todoDefaultFilter, default: .all)
        newItemList = options[ItemOption.todoNewItemList].flatMap { $0.isEmpty ? nil : $0 }
        hidden = options[ItemOption.hiddenTodoLists].map { text in
            Set(text.split(separator: ",").map(String.init))
        }
    }

    public func shows(_ list: CalendarChoice) -> Bool {
        !(hidden?.contains(list.id) ?? false)
    }

    /// The stored value after one list is shown or hidden.
    public func stored(after list: CalendarChoice, isShown: Bool) -> String {
        var names = hidden ?? []
        if isShown {
            names.remove(list.id)
        } else {
            names.insert(list.id)
        }
        return names.sorted().joined(separator: ",")
    }

    /// Open items first, then the ticked ones still on the list, the latest of them first.
    public func arranged(_ items: [TodoItem], now: Date) -> [TodoItem] {
        let open = items.filter { !$0.isCompleted }
        let oldest = completed.seconds.map { now.addingTimeInterval(-$0) }
        let done = items.filter { item in
            guard item.isCompleted, let oldest, let finished = item.completedAt else { return false }
            return finished >= oldest
        }
        return sorted(open) + done.sorted { ($0.completedAt ?? now) > ($1.completedAt ?? now) }
    }

    private func sorted(_ items: [TodoItem]) -> [TodoItem] {
        switch sort {
        case .manual:
            items
        case .title:
            items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dueDate:
            // No date goes last, and the sort has to keep the list's order among equals.
            items.enumerated().sorted { first, second in
                let left = first.element.due ?? .distantFuture
                let right = second.element.due ?? .distantFuture
                return left == right ? first.offset < second.offset : left < right
            }.map(\.element)
        }
    }
}

public enum TodoFilter: String, Codable, CaseIterable, Sendable {
    case all, today, overdue, flagged

    public func apply(to items: [TodoItem], now: Date, calendar: Calendar = .current) -> [TodoItem] {
        items.filter { item in
            guard !item.isCompleted else { return false }
            switch self {
            case .all: return true
            // Reminders has no flag that apps can read, so "flagged" is the high priority.
            case .flagged: return item.level == .high
            case .overdue: return item.due.map { $0 < calendar.startOfDay(for: now) } ?? false
            case .today: return item.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            }
        }
    }
}

public extension TodoFilter {
    /// How many open reminders each filter would show.
    static func counts(in items: [TodoItem], now: Date, calendar: Calendar = .current) -> [TodoFilter: Int] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.apply(to: items, now: now, calendar: calendar).count) })
    }
}

/// One of the Mac's calendars, as a row in Settings.
public struct CalendarChoice: Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var account: String
    public var color: String
    public var isBirthdays: Bool
    /// False for a list that nothing can be added to.
    public var isEditable: Bool

    public init(
        id: String, title: String, account: String, color: String, isBirthdays: Bool = false, isEditable: Bool = true
    ) {
        self.id = id
        self.title = title
        self.account = account
        self.color = color
        self.isBirthdays = isBirthdays
        self.isEditable = isEditable
    }
}

/// Which calendars feed the panels, the menu bar, the Dock and the widgets.
public struct CalendarOptions: Sendable, Equatable {
    /// Nil until the first choice: everything shows except birthdays, which are not meetings.
    private var hidden: Set<String>?

    public init() {}

    public init(options: [String: String]) {
        hidden = options[ItemOption.hiddenCalendars].map { text in
            Set(text.split(separator: ",").map(String.init))
        }
    }

    public func shows(_ calendar: CalendarChoice) -> Bool {
        hidden.map { !$0.contains(calendar.id) } ?? !calendar.isBirthdays
    }

    /// The stored value after one row changes. The first choice also records the others as they look now.
    public func stored(after calendar: CalendarChoice, isShown: Bool, among all: [CalendarChoice]) -> String {
        var names = hidden ?? Set(all.filter { !shows($0) }.map(\.id))
        if isShown {
            names.remove(calendar.id)
        } else {
            names.insert(calendar.id)
        }
        return names.sorted().joined(separator: ",")
    }
}
