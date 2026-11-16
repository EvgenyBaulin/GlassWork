import GlassWorkCore
import SwiftUI

/// How a reminder's due date and priority read in a widget.
enum TodoLabels {
    /// `Today`, `Tomorrow`, `Yesterday`, a weekday within the coming week, otherwise `Nov 24`.
    static func due(_ due: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)
        ).day ?? 0
        switch days {
        case 0: return loc("Today")
        case 1: return loc("Tomorrow")
        case -1: return loc("Yesterday")
        case 2 ... 6: return due.formatted(.dateTime.weekday(.abbreviated))
        default: return due.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    static func isOverdue(_ due: Date, now: Date, calendar: Calendar = .current) -> Bool {
        due < calendar.startOfDay(for: now)
    }

    /// Reminders' own marks: high is `!!!`, medium `!!`, low `!`. Nil when there is no priority.
    static func priorityMarks(_ priority: Int?) -> String? {
        switch priority ?? 0 {
        case 1 ... 4: "!!!"
        case 5: "!!"
        case 6 ... 9: "!"
        default: nil
        }
    }
}

/// Open reminders of one list, in the order they came.
struct TodoGroup: Identifiable, Equatable {
    var name: String
    var color: String
    var items: [TodoItem]

    var id: String {
        name
    }

    static func groups(of items: [TodoItem]) -> [TodoGroup] {
        var groups: [TodoGroup] = []
        for item in items {
            if let index = groups.firstIndex(where: { $0.name == item.listName }) {
                groups[index].items.append(item)
            } else {
                groups.append(TodoGroup(name: item.listName, color: item.listColor, items: [item]))
            }
        }
        return groups
    }

    static let headerHeight: CGFloat = 22
    static let rowHeight: CGFloat = 22
    static let rowsPerGroup = 5

    /// Groups flowed into columns of a given height; what does not fit is counted.
    static func columns(
        of groups: [TodoGroup], count: Int, height: CGFloat
    ) -> (columns: [[TodoGroup]], hidden: Int) {
        var columns: [[TodoGroup]] = [[]]
        var used: CGFloat = 0
        var hidden = 0
        for group in groups {
            var shown = group
            shown.items = Array(group.items.prefix(rowsPerGroup))
            let cost = headerHeight + rowHeight * CGFloat(shown.items.count)
            if used + cost > height, !columns[columns.count - 1].isEmpty {
                if columns.count < count {
                    columns.append([])
                    used = 0
                } else {
                    hidden += group.items.count
                    continue
                }
            }
            columns[columns.count - 1].append(shown)
            used += cost
            hidden += group.items.count - shown.items.count
        }
        return (columns, hidden)
    }
}

/// One reminder: a round button that ticks it, its title and what is known about it.
struct WidgetTodoRow: View {
    let item: TodoItem
    let now: Date
    var showsList = false
    var showsDue = true

    var body: some View {
        HStack(spacing: 6) {
            WidgetActionButton(action: .setTodo(id: item.id, completed: true)) {
                Image(systemName: "circle").foregroundStyle(Color(hex: item.listColor))
            }
            Text(item.title).lineLimit(1)
            if let marks = TodoLabels.priorityMarks(item.priority) {
                Text(marks).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.orange)
            } else if item.isFlagged {
                Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Palette.orange)
            }
            Spacer(minLength: 2)
            if showsList, !item.listName.isEmpty {
                Text(item.listName)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
            if showsDue, let due = item.due {
                Text(TodoLabels.due(due, now: now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TodoLabels.isOverdue(due, now: now) ? Palette.red : .secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .font(.system(size: 13))
        .frame(height: TodoGroup.rowHeight)
    }
}

/// The "add" control of the larger sizes: it opens the To-Dos panel, which has the field for a new reminder.
struct TodoAddLink: View {
    var body: some View {
        if let url = WidgetLink.url(for: .todos) {
            Link(destination: url) {
                Label(loc("Add"), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .widgetSolid(Palette.blue, in: .capsule)
                    .contentShape(.capsule)
            }
        }
    }
}
