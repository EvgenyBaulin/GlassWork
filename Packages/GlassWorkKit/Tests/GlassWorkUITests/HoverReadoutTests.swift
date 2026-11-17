import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

struct HoverReadoutTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: 15))!
    }

    // MARK: Ring

    @Test func ringHitSplitsUsedAndFreeClockwiseFromTop() {
        let size = CGSize(width: 100, height: 100)
        // 25 % used: the arc ends at three o'clock.
        let top = CGPoint(x: 50, y: 4)
        let right = CGPoint(x: 96, y: 48)
        let left = CGPoint(x: 4, y: 50)
        #expect(RingHit.part(at: CGPoint(x: 70, y: 6), size: size, lineWidth: 8, value: 0.25) == .used)
        #expect(RingHit.part(at: top, size: size, lineWidth: 8, value: 0.25) == .used)
        #expect(RingHit.part(at: right, size: size, lineWidth: 8, value: 0.25) == .used)
        #expect(RingHit.part(at: left, size: size, lineWidth: 8, value: 0.25) == .free)
        #expect(RingHit.part(at: CGPoint(x: 30, y: 6), size: size, lineWidth: 8, value: 0.25) == .free)
    }

    @Test func ringHitIgnoresTheCenterAndOutside() {
        let size = CGSize(width: 100, height: 100)
        #expect(RingHit.part(at: CGPoint(x: 50, y: 50), size: size, lineWidth: 8, value: 0.5) == nil)
        #expect(RingHit.part(at: CGPoint(x: 1, y: 1), size: size, lineWidth: 8, value: 0.5) == nil)
    }

    @Test func thinRingsKeepAnEightPointBand() {
        let size = CGSize(width: 100, height: 100)
        // A 2 pt ring still answers 3.5 pt inside its edge.
        #expect(RingHit.part(at: CGPoint(x: 50, y: 3.5), size: size, lineWidth: 2, value: 0.5) == .used)
        #expect(RingHit.part(at: CGPoint(x: 50, y: 12), size: size, lineWidth: 2, value: 0.5) == nil)
    }

    @Test func ringRowNamesTheHoveredPartWithItsShare() {
        let readout = RingReadout(usedTitle: "Free", freeTitle: "Used", usedValue: "40 GB", freeValue: "60 GB")
        let used = readout.row(for: .used, value: 0.4, tint: .green)
        let free = readout.row(for: .free, value: 0.4, tint: .green)
        #expect(used.title == "Free")
        #expect(used.value == "40 GB · \(Format.percent(0.4))")
        #expect(free.title == "Used")
        #expect(free.value == "60 GB · \(Format.percent(0.6))")
        let bare = RingReadout(usedTitle: "A", freeTitle: "B").row(for: .used, value: 0.5, tint: .green)
        #expect(bare.value == Format.percent(0.5))
    }

    // MARK: Tooltip and motion

    @Test func tooltipFlipsLeftAtTheRightEdgeAndStaysInside() {
        #expect(TooltipPlacement.x(20, width: 80, container: 300) == 36)
        #expect(TooltipPlacement.x(280, width: 80, container: 300) == 184)
        #expect(TooltipPlacement.x(150, width: 280, container: 300) == 10)
    }

    @Test func narrowViewsCenterTheTooltip() {
        #expect(TooltipPlacement.x(forSmallView: 10, width: 100, container: 60) == -20)
        #expect(TooltipPlacement.x(forSmallView: 20, width: 80, container: 300) == 36)
    }

    @Test func tooltipOpensTowardTheRoomInsideTheView() {
        #expect(!TooltipPlacement.opensAbove(cursorY: 10, container: 100))
        #expect(TooltipPlacement.opensAbove(cursorY: 90, container: 100))
        #expect(TooltipPlacement.top(cursorY: 10, height: 30, container: 100) == 24)
        #expect(TooltipPlacement.top(cursorY: 90, height: 30, container: 100) == 46)
    }

    @Test func reduceMotionDropsTheHoverAnimation() {
        #expect(HoverMotion.animation(reduceMotion: true) == nil)
        #expect(HoverMotion.animation(reduceMotion: false) != nil)
    }

    @Test func hoverAreaIsAtLeastEightPoints() {
        #expect(HoverMotion.hitSize(of: CGSize(width: 120, height: 4)) == CGSize(width: 120, height: 8))
        #expect(HoverMotion.hitSize(of: CGSize(width: 5, height: 5)) == CGSize(width: 8, height: 8))
        #expect(HoverMotion.hitSize(of: CGSize(width: 50, height: 40)) == CGSize(width: 50, height: 40))
    }

    // MARK: Dates

    @Test func relativeDaysCountCalendarDaysFromNow() throws {
        let now = date(2026, 3, 10)
        #expect(RelativeDay(of: date(2026, 3, 10), now: now, calendar: utc) == .today)
        #expect(RelativeDay(of: date(2026, 3, 11), now: now, calendar: utc) == .tomorrow)
        #expect(RelativeDay(of: date(2026, 3, 9), now: now, calendar: utc) == .yesterday)
        #expect(RelativeDay(of: date(2026, 3, 22), now: now, calendar: utc) == .ahead(12))
        #expect(RelativeDay(of: date(2026, 3, 7), now: now, calendar: utc) == .behind(3))
        // Late evening today and early morning tomorrow are still a day apart.
        let late = try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 23, minute: 59)))
        let early = try #require(utc.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 0, minute: 1)))
        #expect(RelativeDay(of: early, now: late, calendar: utc) == .tomorrow)
    }

    @Test func relativeTextMentionsTheNumberOfDays() {
        #expect(RelativeDay.ahead(12).text.contains("12"))
        #expect(RelativeDay.behind(3).text.contains("3"))
    }

    @Test func yearDotsMapToDaysOfTheYear() {
        let now = date(2026, 3, 10)
        let first = DotReadout.yearDay(index: 0, now: now, calendar: utc)
        let last = DotReadout.yearDay(index: 364, now: now, calendar: utc)
        #expect(first == utc.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(last == utc.date(from: DateComponents(year: 2026, month: 12, day: 31)))
    }

    @Test func dayRowShowsWeekdayDateAndRelativeTime() {
        let now = date(2026, 3, 10)
        let row = DotReadout.dayRow(date(2026, 3, 22), now: now, tint: .orange, calendar: utc)
        #expect(row.value == RelativeDay.ahead(12).text)
        #expect(row.title.contains("22"))
    }

    // MARK: Dot rows and heat map

    @Test func dotIndexFollowsEqualCells() {
        #expect(DotReadout.dotIndex(x: 0, width: 300, count: 30) == 0)
        #expect(DotReadout.dotIndex(x: 95, width: 300, count: 30) == 9)
        #expect(DotReadout.dotIndex(x: 299.9, width: 300, count: 30) == 29)
        #expect(DotReadout.dotIndex(x: 300, width: 300, count: 30) == nil)
        #expect(DotReadout.dotIndex(x: -1, width: 300, count: 30) == nil)
    }

    @Test func rangeRowsShowTheDotAndTheWholeRange() {
        let range = DateInterval(start: date(2026, 3, 1), end: date(2026, 4, 1))
        let rows = DotReadout.rangeRows(index: 14, count: 30, range: range, tint: .green)
        #expect(rows.count == 2)
        #expect(rows[0].value == Format.percent(0.5))
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        #expect(rows[1]
            .value == "\(range.start.formatted(style)) – \(range.end.addingTimeInterval(-1).formatted(style))")
        let slice = DotReadout.slice(index: 3, count: 4, range: DateInterval(start: .distantPast, duration: 400))
        #expect(slice.duration == 100)
    }

    @Test func heatMapCellsFillColumnsTopToBottom() {
        #expect(HeatMap.index(at: CGPoint(x: 4, y: 4), count: 100) == 0)
        #expect(HeatMap.index(at: CGPoint(x: 4, y: 64), count: 100) == 6)
        #expect(HeatMap.index(at: CGPoint(x: 14, y: 4), count: 100) == 7)
        // The gap between cells belongs to a cell.
        #expect(HeatMap.index(at: CGPoint(x: 9, y: 9), count: 100) == 0)
        #expect(HeatMap.index(at: CGPoint(x: 4, y: 71), count: 100) == nil)
        #expect(HeatMap.index(at: CGPoint(x: 4, y: 4), count: 0) == nil)
        #expect(HeatMap.index(at: CGPoint(x: 24, y: 4), count: 14) == nil)
    }

    // MARK: Limit bars

    @Test func limitBarBreakdownListsUsedLeftAndReset() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AIWindow(kind: .fiveHour, used: 0.3, resetsAt: now.addingTimeInterval(3600))
        let rows = AIWindowText.breakdown(window, now: now, tint: .green)
        #expect(rows.count == 3)
        #expect(rows[0].value == Format.percent(0.3, style: .precise))
        #expect(rows[1].value == Format.percent(0.7, style: .precise))
    }

    @Test func limitBarBreakdownAfterResetIsEmptyAndHasNoResetRow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AIWindow(kind: .week, used: 0.9, resetsAt: now.addingTimeInterval(-60))
        let rows = AIWindowText.breakdown(window, now: now, tint: .green)
        #expect(rows.count == 2)
        #expect(rows[0].value == Format.percent(0, style: .precise))
    }
}
