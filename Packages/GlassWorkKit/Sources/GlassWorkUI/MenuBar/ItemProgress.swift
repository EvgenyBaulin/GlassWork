import Foundation
import GlassWorkCore

/// How far along an item is, from 0 to 1, for the Graph style of items that have no history to draw.
enum ItemProgress {
    /// Span a countdown to a date is measured over: a date a year away or more shows an empty bar.
    static let countdownSpan: TimeInterval = 365 * 86400
    /// Look-ahead used when the Calendar window is set to unlimited.
    static let defaultWindow: TimeInterval = 24 * 3600

    static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    /// A current event is the share elapsed; an upcoming one fills as it nears, over the look-ahead window.
    static func calendar(_ state: CalendarItemState?, at now: Date, windowHours: Int) -> Double {
        switch state {
        case let .current(event, _):
            event.progress(at: now)
        case let .upcoming(_, startsIn):
            approach(startsIn, window: windowHours > 0 ? TimeInterval(windowHours) * 3600 : defaultWindow)
        case let .callSoon(event):
            approach(event.start.timeIntervalSince(now), window: CalendarItem.callLead)
        case nil:
            0
        }
    }

    /// Share of the event in progress that has passed. A free calendar is an empty bar.
    static func endsIn(_ state: EndsInState, at now: Date) -> Double {
        state.current.first?.progress(at: now) ?? 0
    }

    /// Share of the timer's own length that has run.
    static func timer(_ timer: CountdownTimer?, at now: Date) -> Double {
        guard let timer, timer.duration > 0 else { return 0 }
        return clamp(1 - timer.remaining(at: now) / timer.duration)
    }

    /// Share of the nearest date's last year that has passed. Dates that are gone are full.
    static func countdown(_ dates: [ImportantDate], at now: Date, calendar: Calendar = .current) -> Double {
        let left = dates.map { max(calendar.startOfDay(for: $0.date).timeIntervalSince(now), 0) }
        guard let nearest = left.min() else { return 0 }
        return clamp(1 - nearest / countdownSpan)
    }

    /// Share of today's reminders that are ticked: those due today and those ticked today.
    static func todos(_ items: [TodoItem], at now: Date, calendar: Calendar = .current) -> Double {
        let today = items.filter { item in
            item.due.map { calendar.isDate($0, inSameDayAs: now) } == true
                || item.completedAt.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        guard !today.isEmpty else { return 0 }
        return Double(today.filter(\.isCompleted).count) / Double(today.count)
    }

    /// Daylight between sunrise and sunset; at night the moon's place in its cycle.
    static func sunMoon(at now: Date, latitude: Double, longitude: Double) -> Double {
        let times = Astronomy.sunTimes(on: now, latitude: latitude, longitude: longitude)
        if let rise = times.sunrise, let set = times.sunset, rise <= now, now < set {
            return clamp(now.timeIntervalSince(rise) / set.timeIntervalSince(rise))
        }
        return Astronomy.moonAge(at: now)
    }

    /// The lowest charge, as that is the device that will need attention first.
    static func lowestBattery(_ devices: [DeviceBattery]) -> Double {
        clamp(devices.map(\.charge).min() ?? 0)
    }

    private static func approach(_ remaining: TimeInterval, window: TimeInterval) -> Double {
        guard window > 0 else { return 0 }
        return clamp(1 - remaining / window)
    }
}
