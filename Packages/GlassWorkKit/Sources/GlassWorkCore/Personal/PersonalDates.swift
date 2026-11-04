import Foundation

/// A contact's birthday as it comes out of Contacts. The year is often unknown.
public struct ContactBirthday: Sendable, Equatable {
    public var id: String
    public var name: String
    public var month: Int
    public var day: Int
    public var year: Int?

    public init(id: String, name: String, month: Int, day: Int, year: Int? = nil) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
        self.year = year
    }

    /// Nil when the date cannot be placed on the Gregorian calendar, such as a lunar date with no year.
    public init?(id: String, name: String, components: DateComponents) {
        var parts = components
        if let calendar = parts.calendar, calendar.identifier != .gregorian {
            guard parts.year != nil, let date = calendar.date(from: parts) else { return nil }
            var gregorian = Calendar(identifier: .gregorian)
            gregorian.timeZone = calendar.timeZone
            parts = gregorian.dateComponents([.year, .month, .day], from: date)
        }
        guard let month = parts.month, let day = parts.day, (1 ... 12).contains(month), (1 ... 31).contains(day) else {
            return nil
        }
        self.init(id: id, name: name, month: month, day: day, year: parts.year)
    }
}

/// Puts birthdays on the calendar. Pure, so the awkward days can be tested.
public enum BirthdayPlanner {
    /// A date Contacts could never mean, such as 31 April, is dropped by the caller as nil.
    ///
    /// February 29 is marked on the 28th in other years.
    public static func next(
        _ birthday: ContactBirthday,
        onOrAfter date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let today = calendar.startOfDay(for: date)
        let thisYear = calendar.component(.year, from: date)
        for year in thisYear ... thisYear + 1 {
            guard let candidate = day(of: birthday, in: year, calendar: calendar) else { return nil }
            if candidate >= today {
                return candidate
            }
        }
        return nil
    }

    private static func day(of birthday: ContactBirthday, in year: Int, calendar: Calendar) -> Date? {
        let wanted = DateComponents(year: year, month: birthday.month, day: birthday.day)
        if let date = calendar.date(from: wanted), calendar.component(.day, from: date) == birthday.day {
            return calendar.startOfDay(for: date)
        }
        guard birthday.month == 2, birthday.day == 29 else { return nil }
        return calendar.date(from: DateComponents(year: year, month: 2, day: 28))
    }

    /// Soonest first; people on the same day stay in name order.
    public static func upcoming(
        _ birthdays: [ContactBirthday],
        at date: Date,
        limit: Int,
        calendar: Calendar = .current
    ) -> [WidgetBirthday] {
        let planned = birthdays.compactMap { birthday -> WidgetBirthday? in
            guard let next = next(birthday, onOrAfter: date, calendar: calendar) else { return nil }
            let turns = birthday.year.map { calendar.component(.year, from: next) - $0 }
            return WidgetBirthday(id: birthday.id, name: birthday.name, date: next, turns: turns.flatMap {
                $0 > 0 ? $0 : nil
            })
        }
        let sorted = planned.sorted {
            $0.date == $1.date ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.date < $1.date
        }
        return Array(sorted.prefix(limit))
    }

    /// Whole days from `date` to the birthday; 0 on the day itself.
    public static func daysUntil(_ birthday: WidgetBirthday, from date: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: birthday.date).day ?? 0
    }
}

/// Which day of past years counts as "this day".
public enum OnThisDay {
    public static let yearsBack = 30

    /// One day in each past year. On February 28 of a common year, leap days count too.
    public static func days(before date: Date, calendar: Calendar = .current) -> [DateInterval] {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return [] }
        let isLastDayOfFebruary = month == 2 && day == 28 && !isLeap(year, calendar)
        return (1 ... yearsBack).flatMap { back -> [DateInterval] in
            var found = interval(year: year - back, month: month, day: day, calendar: calendar).map { [$0] } ?? []
            if isLastDayOfFebruary, let leap = interval(year: year - back, month: 2, day: 29, calendar: calendar) {
                found.append(leap)
            }
            return found
        }
    }

    private static func isLeap(_ year: Int, _ calendar: Calendar) -> Bool {
        interval(year: year, month: 2, day: 29, calendar: calendar) != nil
    }

    private static func interval(year: Int, month: Int, day: Int, calendar: Calendar) -> DateInterval? {
        let parts = DateComponents(year: year, month: month, day: day)
        guard let start = calendar.date(from: parts), calendar.component(.day, from: start) == day else { return nil }
        return calendar.dateInterval(of: .day, for: start)
    }

    /// Whole years between a photo and today.
    public static func yearsAgo(_ photo: Date, from date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date) - calendar.component(.year, from: photo)
    }
}

/// How a photo widget moves through its photos. The extension works this out by itself, so a change of photo costs
/// no reload from the app.
public enum PhotoRotation {
    public static let interval: TimeInterval = 900

    public static func index(at date: Date, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(date.timeIntervalSince1970 / interval) % count
    }

    /// The same order all day, and another one tomorrow.
    public static func daySeed(_ date: Date, calendar: Calendar = .current) -> UInt64 {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return UInt64(max((parts.year ?? 0) * 10000 + (parts.month ?? 0) * 100 + (parts.day ?? 0), 0))
    }

    public static func shuffled<Item>(_ items: [Item], seed: UInt64) -> [Item] {
        var result = items
        var state = seed
        for index in result.indices.dropLast().reversed() {
            // SplitMix64: `shuffled()` from the standard library cannot be repeated.
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            result.swapAt(index, Int(value % UInt64(index + 1)))
        }
        return result
    }
}
