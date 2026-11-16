import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetTodoSensorTests {
    private func object(_ snapshot: WidgetSnapshot) throws -> [String: Any] {
        let data = try JSONEncoder().encode(snapshot)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func aSnapshotWithoutTheNewTodoFieldsStillDecodes() throws {
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.todos = [TodoItem(id: "1", title: "Ship", listName: "Work", priority: 5)]
        snapshot.todoSummary = WidgetTodoSummary(open: 1, done: 0)
        snapshot.remindersAccess = .denied
        var json = try object(snapshot)
        json["todoSummary"] = nil
        json["remindersAccess"] = nil
        var todos = try #require(json["todos"] as? [[String: Any]])
        todos[0]["priority"] = nil
        json["todos"] = todos
        let decoded = try JSONDecoder().decode(
            WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json)
        )
        #expect(decoded.todoSummary == nil)
        #expect(decoded.remindersAccess == nil)
        #expect(decoded.todos.first?.priority == nil)
        #expect(decoded.todos.first?.title == "Ship")
    }

    @Test func theNewTodoFieldsRoundTrip() throws {
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.todos = [TodoItem(id: "1", title: "Ship", listName: "Work", priority: 1)]
        snapshot.todoSummary = WidgetTodoSummary(open: 4, done: 2)
        snapshot.remindersAccess = .notAsked
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.todoSummary?.total == 6)
    }

    @Test func aLongListIsCutButTheCountsStayTrue() {
        let open = (0 ..< 100).map { TodoItem(id: "o\($0)", title: "Open \($0)", listName: "A") }
        let done = (0 ..< 30).map { TodoItem(id: "d\($0)", title: "Done \($0)", listName: "A", isCompleted: true) }
        let capped = WidgetTodoSummary.capped(done + open)
        #expect(capped.items.count == WidgetTodoSummary.openLimit + WidgetTodoSummary.doneLimit)
        #expect(capped.items.prefix(WidgetTodoSummary.openLimit).allSatisfy { !$0.isCompleted })
        #expect(capped.summary == WidgetTodoSummary(open: 100, done: 30))
    }

    @Test func theSensorListIsCutButTheCpuReadingsStay() {
        var readings = (0 ..< 400).map { SensorReading(key: String(format: "Tx%03d", $0), group: .other, celsius: 40) }
        readings += [
            SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 60),
            SensorReading(key: "Te01", group: .cpuEfficiency, celsius: 50),
        ]
        let sample = SensorSample(
            readings: readings,
            fans: [FanReading(id: 0, rpm: 2000, minimum: 1000, maximum: 5000)]
        )
        let capped = sample.cappedForWidgets()
        #expect(capped.readings.count == SensorSample.widgetLimit)
        #expect(capped.averageCPU == 55)
        #expect(capped.fans == sample.fans)
    }

    @Test func aSmallSensorListIsKeptWhole() {
        let sample = SensorSample(readings: [SensorReading(key: "Tg01", group: .gpu, celsius: 44)], fans: [])
        #expect(sample.cappedForWidgets().readings == sample.readings)
    }
}
