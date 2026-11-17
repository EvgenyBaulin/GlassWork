import Foundation
import GlassWorkCore
import SwiftUI

/// How far a day is from today, in whole calendar days.
enum RelativeDay: Equatable {
    case today
    case tomorrow
    case yesterday
    case ahead(Int)
    case behind(Int)

    init(of date: Date, now: Date, calendar: Calendar = .current) {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch days {
        case 0: self = .today
        case 1: self = .tomorrow
        case -1: self = .yesterday
        case let days where days > 0: self = .ahead(days)
        default: self = .behind(-days)
        }
    }

    var text: String {
        switch self {
        case .today: loc("Today")
        case .tomorrow: loc("Tomorrow")
        case .yesterday: loc("Yesterday")
        case let .ahead(days): loc("in \(days) days")
        case let .behind(days): loc("\(days) days ago")
        }
    }
}

/// Readouts for rows of dots: one dot per day of the year, or one dot per slice of a date range.
enum DotReadout {
    /// The day a dot of Year in Dots stands for; `index` counts from 0 on the first of January.
    static func yearDay(index: Int, now: Date, calendar: Calendar = .current) -> Date? {
        guard let first = calendar.dateInterval(of: .year, for: now)?.start else { return nil }
        return calendar.date(byAdding: .day, value: index, to: first)
    }

    /// Date with weekday, then how far away it is.
    static func dayRow(_ date: Date, now: Date, tint: Color, calendar: Calendar = .current) -> HoverRow {
        HoverRow(
            title: date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
            value: RelativeDay(of: date, now: now, calendar: calendar).text,
            color: tint
        )
    }

    /// The dot under a horizontal position in a row of `count` equal cells.
    static func dotIndex(x: CGFloat, width: CGFloat, count: Int) -> Int? {
        guard count > 0, width > 0, x >= 0, x < width else { return nil }
        return min(Int(x / (width / CGFloat(count))), count - 1)
    }

    /// The slice of a range one dot stands for, and the whole range.
    static func slice(index: Int, count: Int, range: DateInterval) -> DateInterval {
        let step = range.duration / Double(max(count, 1))
        return DateInterval(start: range.start.addingTimeInterval(step * Double(index)), duration: step)
    }

    static func rangeRows(
        index: Int,
        count: Int,
        range: DateInterval,
        tint: Color
    ) -> [HoverRow] {
        let slice = slice(index: index, count: count, range: range)
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        // The range's end is the start of the next period, so its last day is the second before.
        let last = range.end.addingTimeInterval(-1)
        return [
            HoverRow(
                title: slice.start.formatted(style),
                value: Format.percent(Double(index + 1) / Double(max(count, 1))),
                color: tint
            ),
            HoverRow(title: loc("Range"), value: "\(range.start.formatted(style)) – \(last.formatted(style))"),
        ]
    }
}
