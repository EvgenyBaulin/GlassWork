import Foundation
@testable import GlassWorkCore
import Testing

struct TodoListTests {
    @Test func remindersPriorityMapsToLevels() {
        #expect(TodoPriority(reminders: 0) == .none)
        #expect([1, 2, 3, 4].allSatisfy { TodoPriority(reminders: $0) == .high })
        #expect(TodoPriority(reminders: 5) == .medium)
        #expect([6, 7, 8, 9].allSatisfy { TodoPriority(reminders: $0) == .low })
    }

    @Test func marksFollowTheLevel() {
        #expect(TodoPriority.high.marks == "!!!")
        #expect(TodoPriority.medium.marks == "!!")
        #expect(TodoPriority.low.marks == "!")
        #expect(TodoPriority.none.marks.isEmpty)
    }

    @Test func aFlaggedItemWithoutPriorityCountsAsHigh() {
        #expect(TodoItem(id: "a", title: "", listName: "", isFlagged: true).level == .high)
        #expect(TodoItem(id: "b", title: "", listName: "").level == .none)
        #expect(TodoItem(id: "c", title: "", listName: "", isFlagged: true, priority: 9).level == .low)
    }

    @Test func theFlaggedFilterMatchesHighPriorityOnly() {
        let items = [
            TodoItem(id: "high", title: "", listName: "", priority: 1),
            TodoItem(id: "medium", title: "", listName: "", priority: 5),
            TodoItem(id: "low", title: "", listName: "", priority: 9),
            TodoItem(id: "none", title: "", listName: ""),
        ]
        #expect(TodoFilter.flagged.apply(to: items, now: Date()).map(\.id) == ["high"])
    }

    @Test func snapshotsWithoutPriorityStillDecode() throws {
        let old = Data(
            ##"{"id":"1","title":"T","listName":"L","listColor":"#3B82F6","isFlagged":false,"isCompleted":false}"##
                .utf8
        )
        let item = try JSONDecoder().decode(TodoItem.self, from: old)
        #expect(item.priority == nil)
        #expect(item.level == .none)
    }

    @Test func groupsKeepTheOrderOfFirstAppearance() {
        let items = [
            TodoItem(id: "1", title: "a", listName: "Work", listColor: "#FF0000"),
            TodoItem(id: "2", title: "b", listName: "Home", listColor: "#00FF00"),
            TodoItem(id: "3", title: "c", listName: "Work", listColor: "#FF0000"),
        ]
        let groups = TodoGroup.groups(of: items)
        #expect(groups.map(\.name) == ["Work", "Home"])
        #expect(groups[0].items.map(\.id) == ["1", "3"])
        #expect(groups[0].color == "#FF0000")
    }

    @Test func optionsDefaultToEveryListGroupedWithAllShown() {
        let options = TodoOptions(options: [:])
        #expect(options.groupsByList)
        #expect(options.defaultFilter == .all)
        #expect(options.newItemList == nil)
        #expect(options.shows(CalendarChoice(id: "x", title: "X", account: "", color: "#000000")))
    }

    @Test func optionsReadWhatSettingsStore() {
        let options = TodoOptions(options: [
            ItemOption.todoGroupsByList: "false",
            ItemOption.todoDefaultFilter: "today",
            ItemOption.todoNewItemList: "home",
            ItemOption.hiddenTodoLists: "work,old",
        ])
        #expect(!options.groupsByList)
        #expect(options.defaultFilter == .today)
        #expect(options.newItemList == "home")
        let work = CalendarChoice(id: "work", title: "Work", account: "", color: "#000000")
        let home = CalendarChoice(id: "home", title: "Home", account: "", color: "#000000")
        #expect(!options.shows(work))
        #expect(options.shows(home))
    }

    @Test func anUnknownFilterMeansAll() {
        #expect(TodoOptions(options: [ItemOption.todoDefaultFilter: "nonsense"]).defaultFilter == .all)
    }

    @Test func hidingAndShowingAListRoundTrips() {
        let work = CalendarChoice(id: "work", title: "Work", account: "", color: "#000000")
        let home = CalendarChoice(id: "home", title: "Home", account: "", color: "#000000")
        let hidden = TodoOptions().stored(after: work, isShown: false)
        #expect(hidden == "work")
        let both = TodoOptions(options: [ItemOption.hiddenTodoLists: hidden]).stored(after: home, isShown: false)
        #expect(both == "home,work")
        let back = TodoOptions(options: [ItemOption.hiddenTodoLists: both]).stored(after: work, isShown: true)
        #expect(back == "home")
    }

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var countItems: [TodoItem] {
        [
            TodoItem(id: "1", title: "Late", listName: "L", due: now.addingTimeInterval(-3 * 86400)),
            TodoItem(id: "2", title: "Today", listName: "L", due: now),
            TodoItem(id: "3", title: "Someday", listName: "L"),
            TodoItem(id: "4", title: "Done", listName: "L", isCompleted: true),
        ]
    }

    @Test func eachCountModeCountsItsOwnItems() {
        let items = Self.countItems
        #expect(TodoCountMode.open.count(in: items, now: Self.now) == 3)
        #expect(TodoCountMode.dueToday.count(in: items, now: Self.now) == 1)
        #expect(TodoCountMode.overdue.count(in: items, now: Self.now) == 1)
    }

    @Test func undatedItemsAreIncludedUnlessTurnedOff() {
        #expect(TodoOptions(options: [:]).includesUndated)
        #expect(TodoOptions(options: [:]).countMode == .open)
        let all = TodoOptions(options: [:]).arranged(Self.countItems, now: Self.now)
        #expect(all.map(\.id) == ["1", "2", "3"])
        let dated = TodoOptions(options: [ItemOption.todoIncludesUndated: "false"])
            .arranged(Self.countItems, now: Self.now)
        #expect(dated.map(\.id) == ["1", "2"])
        #expect(TodoOptions(options: [ItemOption.todoCountMode: "overdue"]).countMode == .overdue)
        #expect(TodoOptions(options: [ItemOption.todoCountMode: "nonsense"]).countMode == .open)
    }
}
