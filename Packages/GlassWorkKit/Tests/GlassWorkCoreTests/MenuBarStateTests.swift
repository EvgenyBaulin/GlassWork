import Foundation
@testable import GlassWorkCore
import Testing

struct CalendarItemStateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let call = URL(string: "https://meet.google.com/abc")

    private func event(
        from start: Double,
        to end: Double,
        call: URL? = nil,
        isAllDay: Bool = false
    ) -> AgendaEvent {
        AgendaEvent(
            id: "\(start)",
            title: "Standup",
            start: now.addingTimeInterval(start * 60),
            end: now.addingTimeInterval(end * 60),
            isAllDay: isAllDay,
            callURL: call
        )
    }

    private func state(_ events: [AgendaEvent], windowHours: Int = 4) -> CalendarItemState? {
        CalendarItem.state(in: events, at: now, windowHours: windowHours, skipsAllDay: true)
    }

    @Test func aFutureEventIsUpcoming() {
        let standup = event(from: 25, to: 40)
        #expect(state([standup]) == .upcoming(standup, startsIn: 1500))
    }

    @Test func anEventInProgressIsCurrent() {
        let standup = event(from: -10, to: 15)
        #expect(state([standup]) == .current(standup, endsIn: 900))
    }

    @Test func aCallWithinFiveMinutesIsCallSoon() {
        let standup = event(from: 5, to: 30, call: call)
        #expect(state([standup]) == .callSoon(standup))
    }

    @Test func aCallSixMinutesAwayIsStillUpcoming() {
        let standup = event(from: 6, to: 30, call: call)
        #expect(state([standup]) == .upcoming(standup, startsIn: 360))
    }

    @Test func anEventWithoutACallLinkIsNeverCallSoon() {
        let standup = event(from: 2, to: 30)
        #expect(state([standup]) == .upcoming(standup, startsIn: 120))
    }

    @Test func aCallComingUpBeatsTheEventInProgress() {
        let running = event(from: -30, to: 3)
        let next = event(from: 4, to: 30, call: call)
        #expect(state([running, next]) == .callSoon(next))
    }

    @Test func theWindowLimitsOnlyTheUpcomingEvent() {
        #expect(state([event(from: 600, to: 630)]) == nil)
        let running = event(from: -10, to: 15)
        #expect(state([running], windowHours: 1) == .current(running, endsIn: 900))
    }

    @Test func nothingScheduledIsNil() {
        #expect(state([]) == nil)
    }
}

struct PressHoldTests {
    private let down = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aQuickPressIsAClick() {
        #expect(PressHold.outcome(down: down, released: down.addingTimeInterval(0.59)) == .click)
    }

    @Test func sixTenthsOfASecondIsAHold() {
        #expect(PressHold.outcome(down: down, released: down.addingTimeInterval(0.6)) == .hold)
        #expect(PressHold.outcome(down: down, released: down.addingTimeInterval(3)) == .hold)
    }

    @Test func aReleaseWithoutAPressIsAClick() {
        #expect(PressHold.outcome(down: nil, released: down) == .click)
    }
}

struct WorldCityOffsetTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let moscow = TimeZone(identifier: "Europe/Moscow")!

    @Test func aCityAheadIsPositive() {
        let city = WorldCity(name: "Dubai", timeZone: "Asia/Dubai")
        #expect(city.offset(from: moscow, at: now) == 3600)
    }

    @Test func aCityBehindIsNegative() {
        let city = WorldCity(name: "San Francisco", timeZone: "America/Los_Angeles")
        #expect(city.offset(from: moscow, at: now) == -11 * 3600)
    }

    @Test func halfHourZonesKeepTheirMinutes() {
        let city = WorldCity(name: "Delhi", timeZone: "Asia/Kolkata")
        #expect(city.offset(from: moscow, at: now) == 2 * 3600 + 1800)
    }

    @Test func theSameZoneIsZero() {
        #expect(WorldCity(name: "Moscow", timeZone: "Europe/Moscow").offset(from: moscow, at: now) == 0)
    }

    @Test func anUnknownZoneReadsAsLocal() {
        let city = WorldCity(name: "Nowhere", timeZone: "Mars/Olympus")
        #expect(city.offset(at: now) == 0)
    }
}
