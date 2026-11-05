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
                if let url = match.url, let host = url.host(), hosts.contains(where: host.hasSuffix) {
                    return url
                }
            }
        }
        return nil
    }
}

/// A reminder from the Reminders app.
public struct TodoItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var listName: String
    public var listColor: String
    public var due: Date?
    public var isFlagged: Bool
    public var isCompleted: Bool
    public var completedAt: Date?

    public init(
        id: String, title: String, listName: String, listColor: String = "#3B82F6",
        due: Date? = nil, isFlagged: Bool = false, isCompleted: Bool = false, completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.listName = listName
        self.listColor = listColor
        self.due = due
        self.isFlagged = isFlagged
        self.isCompleted = isCompleted
        self.completedAt = completedAt
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

    public init() {}

    public init(options: [String: String]) {
        sort = options.choice(ItemOption.todoSort, default: .manual)
        completed = options.choice(ItemOption.todoCompleted, default: .hide)
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
            case .flagged: return item.isFlagged
            case .overdue: return item.due.map { $0 < calendar.startOfDay(for: now) } ?? false
            case .today: return item.due.map { calendar.isDate($0, inSameDayAs: now) } ?? false
            }
        }
    }
}
