import Foundation
@testable import GlassWorkCore
import Testing

struct KeepAwakeRuleTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func battery(_ charge: Double, onAC: Bool) -> BatterySample {
        BatterySample(charge: charge, isCharging: false, isOnAC: onAC)
    }

    @Test
    func untilTurnedOffHasNoEnd() {
        #expect(KeepAwakeRule().end(from: start) == nil)
    }

    @Test
    func aDurationEndsThatLaterOn() {
        let rule = KeepAwakeRule(options: [ItemOption.keepAwakeMinutes: "15"])
        #expect(rule.end(from: start) == start.addingTimeInterval(900))
    }

    @Test
    func itStopsAtTheEndAndNotBefore() {
        let rule = KeepAwakeRule()
        let end = start.addingTimeInterval(60)
        #expect(!rule.shouldStop(endingAt: end, at: start, battery: nil))
        #expect(rule.shouldStop(endingAt: end, at: end, battery: nil))
    }

    @Test
    func itStopsOnALowBattery() {
        let rule = KeepAwakeRule(options: [ItemOption.keepAwakeBatteryFloor: "20"])
        #expect(rule.shouldStop(endingAt: nil, at: start, battery: battery(0.19, onAC: false)))
        #expect(!rule.shouldStop(endingAt: nil, at: start, battery: battery(0.2, onAC: false)))
    }

    @Test
    func aMacOnPowerKeepsGoing() {
        let rule = KeepAwakeRule(options: [ItemOption.keepAwakeBatteryFloor: "20"])
        #expect(!rule.shouldStop(endingAt: nil, at: start, battery: battery(0.05, onAC: true)))
    }

    @Test
    func neverStopsForTheBatteryWhenTurnedOff() {
        let rule = KeepAwakeRule(options: [ItemOption.keepAwakeBatteryFloor: "0"])
        #expect(!rule.shouldStop(endingAt: nil, at: start, battery: battery(0.01, onAC: false)))
    }

    @Test
    func aMacWithoutABatteryKeepsGoing() {
        #expect(!KeepAwakeRule().shouldStop(endingAt: nil, at: start, battery: nil))
    }
}

struct TimerAlertTests {
    @Test
    func aTimerRingsAndNotifiesByDefault() {
        let alert = TimerAlert(options: [:])
        #expect(alert.soundName == "Glass")
        #expect(alert.notifies)
    }

    @Test
    func silenceIsAChoice() {
        let alert = TimerAlert(options: [ItemOption.timerSound: TimerAlert.noSound])
        #expect(alert.soundName == nil)
    }

    @Test
    func theNotificationCanBeTurnedOff() {
        #expect(!TimerAlert(options: [ItemOption.timerNotifies: "false"]).notifies)
    }
}

struct TodoOptionsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func item(_ title: String, due: TimeInterval? = nil, doneAgo: TimeInterval? = nil) -> TodoItem {
        TodoItem(
            id: title,
            title: title,
            listName: "List",
            due: due.map { now.addingTimeInterval($0) },
            isCompleted: doneAgo != nil,
            completedAt: doneAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    private func titles(_ options: TodoOptions, _ items: [TodoItem]) -> [String] {
        options.arranged(items, now: now).map(\.title)
    }

    @Test
    func manualKeepsTheRemindersOrder() {
        #expect(titles(TodoOptions(), [item("b"), item("a"), item("c")]) == ["b", "a", "c"])
    }

    @Test
    func byTitleReadsLikeFinder() {
        var options = TodoOptions()
        options.sort = .title
        #expect(titles(options, [item("item 10"), item("item 2"), item("Apple")]) == ["Apple", "item 2", "item 10"])
    }

    @Test
    func byDueDateLeavesUndatedItemsLast() {
        var options = TodoOptions()
        options.sort = .dueDate
        let items = [item("none"), item("later", due: 200), item("soon", due: 100), item("also none")]
        #expect(titles(options, items) == ["soon", "later", "none", "also none"])
    }

    @Test
    func tickedItemsGoAwayAtOnceByDefault() {
        #expect(titles(TodoOptions(), [item("open"), item("done", doneAgo: 10)]) == ["open"])
    }

    @Test
    func tickedItemsStayForTheChosenTime() {
        var options = TodoOptions()
        options.completed = .day
        let items = [item("old", doneAgo: 90000), item("recent", doneAgo: 10), item("open")]
        #expect(titles(options, items) == ["open", "recent"])
    }

    @Test
    func theLatestTickComesFirst() {
        var options = TodoOptions()
        options.completed = .week
        let items = [item("earlier", doneAgo: 500), item("just now", doneAgo: 5)]
        #expect(titles(options, items) == ["just now", "earlier"])
    }

    @Test
    func anUnknownValueMeansTheDefault() {
        let options = TodoOptions(options: [ItemOption.todoSort: "random", ItemOption.todoCompleted: "never"])
        #expect(options == TodoOptions())
    }
}
