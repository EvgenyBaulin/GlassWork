import Foundation
@testable import GlassWorkCore
import Testing

struct EndsInTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(
        _ id: String,
        from start: Double,
        to end: Double,
        allDay: Bool = false,
        declined: Bool = false
    ) -> AgendaEvent {
        AgendaEvent(
            id: id, title: id,
            start: now.addingTimeInterval(start), end: now.addingTimeInterval(end),
            isAllDay: allDay, isDeclined: declined
        )
    }

    @Test func stacksParallelEventsEndingSoonestFirst() {
        let state = EndsInState(events: [
            event("long", from: -600, to: 3000),
            event("short", from: -60, to: 600),
            event("later", from: 700, to: 900),
        ], at: now)

        #expect(state.current.map(\.id) == ["short", "long"])
        #expect(state.next?.id == "later")
    }

    @Test func skipsAllDayAndDeclinedByDefault() {
        let events = [event("day", from: -100, to: 100, allDay: true), event("no", from: -100, to: 100, declined: true)]
        #expect(EndsInState(events: events, at: now).current.isEmpty)
        #expect(EndsInState(events: events, at: now, includeAllDay: true).current.map(\.id) == ["day"])
    }

    @Test(arguments: [(600.0, EndsInUrgency.normal), (300.0, .soon), (60.0, .lastMinute)])
    func colorsTheLastMinutes(remaining: Double, expected: EndsInUrgency) {
        #expect(EndsInUrgency(remaining: remaining) == expected)
    }

    @Test func listsTimelineChangePoints() {
        let dates = EndsInState.changeDates(
            of: [event("a", from: -10, to: 20), event("b", from: 20, to: 40)],
            after: now
        )
        #expect(dates == [now.addingTimeInterval(20), now.addingTimeInterval(40)])
    }

    @Test func reportsProgress() {
        #expect(event("a", from: -50, to: 50).progress(at: now) == 0.5)
    }
}

struct CallLinkTests {
    @Test func findsAMeetingLink() {
        let url = CallLink.find(in: [nil, "Join: https://us02web.zoom.us/j/123 now"])
        #expect(url?.host() == "us02web.zoom.us")
    }

    @Test func ignoresOtherLinks() {
        #expect(CallLink.find(in: ["https://example.com/agenda"]) == nil)
    }
}

struct TodoFilterTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func filtersByDueAndFlag() {
        let items = [
            TodoItem(id: "old", title: "", listName: "", due: now.addingTimeInterval(-86400 * 2)),
            TodoItem(id: "today", title: "", listName: "", due: now),
            TodoItem(id: "flag", title: "", listName: "", isFlagged: true),
            TodoItem(id: "done", title: "", listName: "", due: now, isCompleted: true),
        ]
        #expect(TodoFilter.all.apply(to: items, now: now).count == 3)
        #expect(TodoFilter.overdue.apply(to: items, now: now).map(\.id) == ["old"])
        #expect(TodoFilter.today.apply(to: items, now: now).map(\.id) == ["today"])
        #expect(TodoFilter.flagged.apply(to: items, now: now).map(\.id) == ["flag"])
    }
}
