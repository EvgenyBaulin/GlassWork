import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct ItemProgressTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func event(from start: TimeInterval, to end: TimeInterval) -> AgendaEvent {
        AgendaEvent(
            id: "e", title: "Sync",
            start: now.addingTimeInterval(start), end: now.addingTimeInterval(end)
        )
    }

    @Test func currentEventIsTheShareElapsed() {
        let current = event(from: -1800, to: 5400)
        let state = CalendarItemState.current(current, endsIn: 5400)
        #expect(abs(ItemProgress.calendar(state, at: now, windowHours: 4) - 0.25) < 0.000_1)
        #expect(abs(ItemProgress.endsIn(EndsInState(events: [current], at: now), at: now) - 0.25) < 0.000_1)
    }

    @Test func upcomingEventFillsAsItNearsOverTheWindow() {
        let next = event(from: 3600, to: 7200)
        let state = CalendarItemState.upcoming(next, startsIn: 3600)
        #expect(abs(ItemProgress.calendar(state, at: now, windowHours: 4) - 0.75) < 0.000_1)
        #expect(abs(ItemProgress.calendar(state, at: now, windowHours: 0) - (1 - 1.0 / 24)) < 0.000_1)
        #expect(ItemProgress.calendar(nil, at: now, windowHours: 4) == 0)
    }

    @Test func freeCalendarIsEmpty() {
        #expect(ItemProgress.endsIn(EndsInState(events: [], at: now), at: now) == 0)
    }

    @Test func timerIsTheShareOfItsLengthThatRan() {
        let timer = CountdownTimer(title: "T", duration: 600, start: now.addingTimeInterval(-150))
        #expect(abs(ItemProgress.timer(timer, at: now) - 0.25) < 0.000_1)
        #expect(ItemProgress.timer(nil, at: now) == 0)
        var paused = CountdownTimer(title: "T", duration: 600, start: now)
        paused.togglePause(at: now.addingTimeInterval(300))
        #expect(abs(ItemProgress.timer(paused, at: now) - 0.5) < 0.000_1)
    }

    @Test func countdownUsesTheNearestDateOverAYear() {
        let half = ImportantDate(title: "A", date: now.addingTimeInterval(182.5 * 86400))
        let far = ImportantDate(title: "B", date: now.addingTimeInterval(900 * 86400))
        let value = ItemProgress.countdown([far, half], at: now, calendar: utc)
        #expect(abs(value - 0.5) < 0.01)
        #expect(ItemProgress.countdown([far], at: now, calendar: utc) == 0)
        #expect(ItemProgress.countdown([], at: now, calendar: utc) == 0)
        let gone = ImportantDate(title: "C", date: now.addingTimeInterval(-5 * 86400))
        #expect(ItemProgress.countdown([gone], at: now, calendar: utc) == 1)
    }

    @Test func todosCountOnlyToday() {
        let today = now
        let old = now.addingTimeInterval(-3 * 86400)
        let items = [
            TodoItem(id: "1", title: "a", listName: "L", due: today, isCompleted: true),
            TodoItem(id: "2", title: "b", listName: "L", due: today),
            TodoItem(id: "3", title: "c", listName: "L", due: today),
            TodoItem(id: "4", title: "d", listName: "L", due: old, isCompleted: true, completedAt: old),
            TodoItem(id: "5", title: "e", listName: "L", due: old),
        ]
        #expect(abs(ItemProgress.todos(items, at: now, calendar: utc) - 1.0 / 3) < 0.000_1)
        #expect(ItemProgress.todos([], at: now, calendar: utc) == 0)
    }

    @Test func sunIsDayProgressAndNightIsTheMoon() {
        let tokyo = (latitude: 35.68, longitude: 139.69)
        // 2026-11-04 at 03:00 UTC is noon in Tokyo, 21:00 UTC is 06:00 the next morning.
        let day = Date(timeIntervalSince1970: 1_793_750_400 + 3 * 3600)
        let noon = ItemProgress.sunMoon(at: day, latitude: tokyo.latitude, longitude: tokyo.longitude)
        #expect(noon > 0.4 && noon < 0.6)
        let night = Date(timeIntervalSince1970: 1_793_750_400 + 12 * 3600)
        let moon = ItemProgress.sunMoon(at: night, latitude: tokyo.latitude, longitude: tokyo.longitude)
        #expect(moon == Astronomy.moonAge(at: night))
        // The sun does not rise at the pole in November.
        let polar = ItemProgress.sunMoon(at: day, latitude: 85, longitude: 0)
        #expect(polar == Astronomy.moonAge(at: day))
    }

    @Test func batteriesShowTheLowest() {
        let devices = [
            DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.8),
            DeviceBattery(name: "Keys", kind: .keyboard, charge: 0.15),
        ]
        #expect(ItemProgress.lowestBattery(devices) == 0.15)
        #expect(ItemProgress.lowestBattery([]) == 0)
    }

    @Test func buildersSupplyTheProgressGlyph() {
        let timer = CountdownTimer(title: "T", duration: 400, start: now.addingTimeInterval(-100))
        #expect(ItemContent.timers([timer], at: now, options: [:]).glyph == .progress(0.25))
        let devices = [DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.5)]
        #expect(ItemContent.deviceBatteries(devices, options: [:]).glyph == .progress(0.5))
        let current = event(from: -100, to: 300)
        #expect(ItemContent.endsIn([current], at: now, options: [:]).glyph == .progress(0.25))
        #expect(ItemContent.calendar([current], at: now, options: [:]).glyph == .progress(0.25))
        #expect(ItemContent.endsIn([], at: now, options: [:]).glyph == .progress(0))
    }
}
