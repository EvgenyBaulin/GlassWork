import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// To-Do and Temperature widgets with a full set of data, and the Fans XL sensor list, in both appearances.
/// Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct WidgetGapSnapshotTests {
    private static let day: TimeInterval = 86400

    private static var sensors: SensorSample {
        var readings: [SensorReading] = []
        for index in 1 ... 6 {
            readings.append(SensorReading(key: "Tp0\(index)", group: .cpuPerformance, celsius: 44 + Double(index)))
        }
        for index in 1 ... 3 {
            readings.append(SensorReading(key: "Te0\(index)", group: .cpuEfficiency, celsius: 38 + Double(index)))
        }
        for index in 1 ... 3 {
            readings.append(SensorReading(key: "Tg0\(index)", group: .gpu, celsius: 41 + Double(index)))
        }
        for index in 1 ... 4 {
            readings.append(SensorReading(key: "Ts0\(index)", group: .soc, celsius: 43 + Double(index)))
        }
        readings += [
            SensorReading(key: "TB0T", group: .battery, celsius: 31),
            SensorReading(key: "TB1T", group: .battery, celsius: 32),
            SensorReading(key: "TH0a", group: .storage, celsius: 38),
            SensorReading(key: "TH0b", group: .storage, celsius: 39),
            SensorReading(key: "TPD0", group: .power, celsius: 36),
            SensorReading(key: "TaLP", group: .ambient, celsius: 29),
            SensorReading(key: "TaRF", group: .ambient, celsius: 30),
            SensorReading(key: "TW0P", group: .other, celsius: 35),
        ]
        for index in 0 ..< 12 {
            readings.append(SensorReading(key: "TXa\(index)", group: .other, celsius: 33 + Double(index)))
        }
        return SensorSample(readings: readings, fans: DataSamples.fans)
    }

    private var temperature: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.sensors = Self.sensors
        return snapshot
    }

    private var fans: WidgetSnapshot {
        var snapshot = DataSamples.fanSnapshot
        snapshot.sensors = Self.sensors
        return snapshot
    }

    private func todos(access: DataAccess? = nil, done: Int = 3) -> WidgetSnapshot {
        let now = sampleNow
        func item(
            _ id: String, _ title: String, _ list: String, _ color: String,
            due: TimeInterval? = nil, flagged: Bool = false, priority: Int? = nil
        ) -> TodoItem {
            TodoItem(
                id: id, title: title, listName: list, listColor: color,
                due: due.map { now.addingTimeInterval($0) }, isFlagged: flagged, priority: priority
            )
        }
        var snapshot = WidgetSnapshot(date: now)
        snapshot.todos = [
            item("1", "Send the invoice", "Work", "#3B82F6", due: -2 * Self.day, priority: 1),
            item("2", "Review the pull request", "Work", "#3B82F6", due: 0, flagged: true),
            item("3", "Buy oat milk", "Home", "#22C55E", due: Self.day),
            item("4", "Book the dentist", "Home", "#22C55E", due: 3 * Self.day, priority: 5),
            item("5", "Renew the passport", "Personal", "#F59E0B", due: 12 * Self.day),
            item("6", "Call the landlord", "Personal", "#F59E0B", priority: 9),
            item("7", "Plan the offsite", "Work", "#3B82F6"),
            item("8", "Water the plants", "Home", "#22C55E"),
        ]
        snapshot.todoSummary = WidgetTodoSummary(open: 8, done: done)
        snapshot.remindersAccess = access
        return snapshot
    }

    private func render(_ kind: WidgetKind, _ snapshot: WidgetSnapshot, name: String, sizes: [WidgetSize]) {
        for size in sizes {
            for dark in [true, false] {
                widgetSnapshot(
                    WidgetFace(kind: kind, size: size, snapshot: snapshot, now: sampleNow),
                    size: size,
                    dark: dark,
                    named: "\(name)-\(size.rawValue)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    @Test func todosWithEverything() {
        render(.todo, todos(), name: "todo", sizes: WidgetSize.allCases)
    }

    @Test func todosWithNothingTickedYet() {
        render(.todo, todos(done: 0), name: "todo-none-done", sizes: [.small, .medium])
    }

    @Test func todosWithoutPermission() {
        render(.todo, todos(access: .denied), name: "todo-denied", sizes: [.small, .medium])
        render(.todo, todos(access: .notAsked), name: "todo-not-asked", sizes: [.large])
    }

    @Test func temperatureWithEverySensor() {
        render(.temperature, temperature, name: "temperature", sizes: WidgetSize.allCases)
    }

    @Test func temperatureOnAFanlessMac() {
        var snapshot = temperature
        snapshot.sensors?.fans = []
        render(.temperature, snapshot, name: "temperature-fanless", sizes: [.small, .medium])
    }

    @Test func fansListEverySensorInTheExtraLargeSize() {
        render(.fans, fans, name: "fans-sensors", sizes: [.extraLarge])
        var curve = fans
        curve.fans?.mode = .curve
        render(.fans, curve, name: "fans-sensors-curve", sizes: [.extraLarge])
    }
}

struct WidgetGapLogicTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let now = Date(timeIntervalSince1970: 1_793_750_000)

    @Test func dueDatesReadAsDaysThenWeekdays() {
        func text(_ days: Double) -> String {
            TodoLabels.due(now.addingTimeInterval(days * 86400), now: now, calendar: calendar)
        }
        #expect(text(0) == "Today")
        #expect(text(1) == "Tomorrow")
        #expect(text(-1) == "Yesterday")
        let weekday = text(3)
        let date = text(30)
        #expect(weekday.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(date.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    @Test func overdueMeansBeforeToday() {
        #expect(TodoLabels.isOverdue(now.addingTimeInterval(-2 * 86400), now: now, calendar: calendar))
        #expect(!TodoLabels.isOverdue(now, now: now, calendar: calendar))
    }

    @Test func prioritiesBecomeMarks() {
        #expect(TodoLabels.priorityMarks(1) == "!!!")
        #expect(TodoLabels.priorityMarks(5) == "!!")
        #expect(TodoLabels.priorityMarks(9) == "!")
        #expect(TodoLabels.priorityMarks(nil) == nil)
        #expect(TodoLabels.priorityMarks(0) == nil)
    }

    @Test func groupsKeepTheOrderListsFirstAppear() {
        let items = [
            TodoItem(id: "1", title: "a", listName: "Work"),
            TodoItem(id: "2", title: "b", listName: "Home"),
            TodoItem(id: "3", title: "c", listName: "Work"),
        ]
        let groups = TodoWidgetGroup.groups(of: items)
        #expect(groups.map(\.name) == ["Work", "Home"])
        #expect(groups[0].items.map(\.id) == ["1", "3"])
    }

    @Test func groupsFlowIntoColumnsAndTheRestIsCounted() {
        let groups = (0 ..< 4).map { index in
            TodoWidgetGroup(
                name: "L\(index)", color: "#000000",
                items: (0 ..< 3).map { TodoItem(id: "\(index)-\($0)", title: "t", listName: "L\(index)") }
            )
        }
        // A group costs a header and three rows: 88 points, so two fit in 180 and the rest go to the next column.
        let layout = TodoWidgetGroup.columns(of: groups, count: 2, height: 180)
        #expect(layout.columns.map(\.count) == [2, 2])
        #expect(layout.hidden == 0)
        let tight = TodoWidgetGroup.columns(of: groups, count: 2, height: 100)
        #expect(tight.columns.map(\.count) == [1, 1])
        #expect(tight.hidden == 6)
    }

    @Test func theSensorListFlowsIntoColumnsAndCountsWhatIsLeft() {
        let readings = (0 ..< 30).map { SensorReading(key: "Tp\($0)", group: .cpuPerformance, celsius: 50) }
            + [SensorReading(key: "Tg01", group: .gpu, celsius: 40)]
        let sample = SensorSample(readings: readings, fans: [])
        let wide = SensorListLayout(sample: sample, columns: 3, height: 300)
        #expect(wide.hidden == 0)
        let rows = wide.columns.flatMap(\.self).filter {
            if case .row = $0 {
                true
            } else {
                false
            }
        }
        #expect(rows.count == 31)
        let narrow = SensorListLayout(sample: sample, columns: 1, height: 100)
        #expect(narrow.hidden > 0)
        #expect(narrow.columns.count == 1)
    }
}
