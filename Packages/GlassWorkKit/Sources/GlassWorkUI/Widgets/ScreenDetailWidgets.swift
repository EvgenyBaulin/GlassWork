import Charts
import GlassWorkCore
import SwiftUI
import WidgetKit

/// Today's time split into kinds of work.
struct CategoriesWidget: View {
    let context: TimeContext
    var chartHover: Date?
    var donutHover: AppCategory?

    private var log: ScreenTimeLog {
        context.snapshot.screenTime
    }

    private var stats: ScreenCategoryStats {
        ScreenCategoryStats(day: log.today(context.now), categories: log.categories)
    }

    private let symbol = "chart.pie.fill"

    var body: some View {
        let stats = stats
        if let top = stats.rows.first {
            switch context.size {
            case .small:
                VStack(spacing: 4) {
                    donut(stats, diameter: 92, lineWidth: 11, figure: 15)
                    Text(top.category.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(top.category.tint)
                        .lineLimit(1)
                    Text(loc("\(WidgetDuration.short(top.seconds)) · \(Format.percent(top.share)) of today"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .medium:
                HStack(spacing: 16) {
                    donut(stats, diameter: 124, lineWidth: 14, figure: 19)
                    VStack(spacing: 6) {
                        ForEach(stats.rows) { legendRow($0) }
                    }
                }
                .frame(maxHeight: .infinity)
            case .large:
                VStack(alignment: .leading, spacing: 13) {
                    title(stats)
                    ForEach(stats.rows) { detailRow($0) }
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        title(stats)
                        donut(stats, diameter: 200, lineWidth: 22, figure: 28).frame(maxWidth: .infinity)
                        Text(loc("Mostly \(top.category.title)"))
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetSection(title: loc("Last 7 days by category"))
                        weekChart
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: symbol, tint: Palette.purple, size: context.size)
        }
    }

    private func title(_ stats: ScreenCategoryStats) -> some View {
        WidgetTitle(
            title: loc("Categories"),
            symbol: symbol,
            tint: Palette.purple,
            note: loc("Today · \(WidgetDuration.short(stats.total))")
        )
    }

    private func donut(
        _ stats: ScreenCategoryStats,
        diameter: CGFloat,
        lineWidth: CGFloat,
        figure: CGFloat
    ) -> some View {
        CategoryDonut(rows: stats.rows, lineWidth: lineWidth, initialHover: donutHover) {
            VStack(spacing: 0) {
                Text(WidgetDuration.short(stats.total)).font(.widgetFigure(figure)).lineLimit(1)
                Text(loc("today")).font(.system(size: figure * 0.6)).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func legendRow(_ row: ScreenCategoryStats.Row) -> some View {
        HStack(spacing: 6) {
            Circle().fill(row.category.tint).frame(width: 7, height: 7)
            Text(row.category.title).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
            Text(WidgetDuration.short(row.seconds)).font(.system(size: 12)).foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func detailRow(_ row: ScreenCategoryStats.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle().fill(row.category.tint).frame(width: 7, height: 7)
                Text(row.category.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(Format.percent(row.share)).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(WidgetDuration.short(row.seconds)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            ThinBar(value: row.share, tint: row.category.tint)
            Text(row.apps.prefix(3).joined(separator: ", "))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var weekChart: some View {
        let days = ScreenWeekStats(log: log, at: context.now).days
        let byKey = Dictionary(log.days.map { ($0.day, $0) }) { first, _ in first }
        let series = AppCategory.allCases.map { category in
            ChartSeries(
                id: category.rawValue,
                title: category.title,
                color: category.tint,
                points: days.map { day in
                    let entry = byKey[ScreenTimeLog.dayKey(day.date)]
                    let row = ScreenCategoryStats(day: entry, categories: log.categories).rows
                        .first { $0.category == category }
                    return History<Double>.Point(date: day.date, value: row?.seconds ?? 0)
                },
                format: { WidgetDuration.short($0) }
            )
        }
        return VStack(spacing: 3) {
            InteractiveChart(
                series: series,
                height: 240,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .stackedBars(unit: .day),
                initialHover: chartHover
            )
            WidgetAxisLabels(labels: days.map { WidgetDuration.weekday($0.date) })
        }
    }
}

/// A ring cut into categories. Hovering a segment highlights it and names it in the middle.
struct CategoryDonut<Center: View>: View {
    let rows: [ScreenCategoryStats.Row]
    let lineWidth: CGFloat
    var initialHover: AppCategory?
    @ViewBuilder let center: () -> Center
    @State private var hover: AppCategory?

    private var hovered: ScreenCategoryStats.Row? {
        rows.first { $0.category == (hover ?? initialHover) }
    }

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            ZStack {
                Chart(rows) { row in
                    SectorMark(
                        angle: .value("Time", row.seconds),
                        innerRadius: .fixed(radius - lineWidth),
                        angularInset: 1.5
                    )
                    .cornerRadius(lineWidth / 4)
                    .foregroundStyle(row.category.tint)
                    .opacity(hovered == nil || hovered == row ? 1 : 0.35)
                }
                .chartLegend(.hidden)
                .widgetAccentable()
                if let hovered {
                    VStack(spacing: 0) {
                        Text(hovered.category.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(WidgetDuration.short(hovered.seconds)).font(.system(size: 11)).monospacedDigit()
                    }
                } else {
                    center()
                }
            }
            .contentShape(.circle)
            .onContinuousHover { phase in
                switch phase {
                case let .active(location): hover = category(at: location, in: geometry.size)
                case .ended: hover = nil
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    /// The segment under a point: angles run clockwise from the top, as the chart draws them.
    private func category(at point: CGPoint, in size: CGSize) -> AppCategory? {
        let angle = atan2(point.x - size.width / 2, size.height / 2 - point.y)
        let turn = (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi)
        return ScreenCategoryStats.row(at: turn, in: rows)?.category
    }
}

/// Time since the last rest. GlassWork only reminds; it never locks the Mac.
struct BreaksWidget: View {
    let context: TimeContext

    private var day: ScreenDay? {
        context.snapshot.screenTime.today(context.now)
    }

    private var stats: ScreenBreakStats {
        ScreenBreakStats(day: day, at: context.now)
    }

    private let symbol = "cup.and.saucer.fill"

    private var ringTint: Color {
        stats.isDueSoon ? Palette.orange : Palette.green
    }

    var body: some View {
        let stats = stats
        if stats.hasData {
            switch context.size {
            case .small:
                VStack(spacing: 3) {
                    header
                    ring(stats, diameter: 78)
                    Text(loc("since last break")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    due(stats).font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .medium:
                HStack(spacing: 14) {
                    VStack(spacing: 4) {
                        header
                        ring(stats, diameter: 96)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        due(stats).font(.system(size: 14, weight: .semibold))
                        Text(loc("Breaks today: \(stats.breaks.count) · \(WidgetDuration.short(stats.totalBreak))"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        timeline(stats)
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 9) {
                    title
                    summary(stats)
                    WidgetSection(title: loc("Today"))
                    timeline(stats)
                    Divider()
                    facts(stats)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        title
                        summary(stats)
                        WidgetSection(title: loc("Today"))
                        timeline(stats)
                        Divider()
                        facts(stats)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetSection(title: loc("Breaks today"))
                        ForEach(Array(stats.breaks.reversed().prefix(6)), id: \.start) { item in
                            HStack(spacing: 8) {
                                Circle().fill(Palette.green).frame(width: 7, height: 7).widgetAccentable()
                                Text(WidgetDuration.clock(item.start)).font(.system(size: 12, weight: .medium))
                                Spacer(minLength: 4)
                                Text(WidgetDuration.short(item.duration))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(loc("A break is 5 minutes or more with the screen locked or asleep."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: symbol, tint: Palette.green, size: context.size)
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Breaks"), symbol: symbol, tint: Palette.green)
    }

    private var title: some View {
        WidgetTitle(
            title: loc("Breaks"),
            symbol: symbol,
            tint: Palette.green,
            note: loc("Every \(Int(ScreenBreakStats.reminderInterval / 60)) min")
        )
    }

    private func ring(_ stats: ScreenBreakStats, diameter: CGFloat) -> some View {
        RingGauge(value: stats.share, tint: ringTint, lineWidth: diameter / 10) {
            Text(WidgetDuration.short(stats.sinceBreak)).font(.widgetFigure(diameter / 4.4)).lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
    }

    private func due(_ stats: ScreenBreakStats) -> some View {
        Group {
            if stats.untilBreak > 0 {
                Text(loc("Break in \(WidgetDuration.short(stats.untilBreak))"))
            } else {
                Text(loc("Time for a break"))
            }
        }
        .foregroundStyle(ringTint)
        .lineLimit(1)
        .widgetAccentable()
    }

    private func summary(_ stats: ScreenBreakStats) -> some View {
        HStack(spacing: 14) {
            ring(stats, diameter: 92)
            VStack(alignment: .leading, spacing: 3) {
                due(stats).font(.system(size: 15, weight: .semibold))
                Text(loc("\(WidgetDuration.short(stats.sinceBreak)) since your last break"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// The day as one bar: focus in purple, breaks in green, from the first session until now.
    private func timeline(_ stats: ScreenBreakStats) -> some View {
        let start = day?.sessions.first?.start ?? context.now
        let span = max(context.now.timeIntervalSince(start), 1)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.purple)
                ForEach(stats.breaks, id: \.start) { item in
                    Rectangle()
                        .fill(Palette.green)
                        .frame(width: max(geometry.size.width * item.duration / span, 2))
                        .offset(x: geometry.size.width * item.start.timeIntervalSince(start) / span)
                        .help(WidgetDuration.range(item.start, item.end))
                }
            }
            .clipShape(.capsule)
        }
        .frame(height: 7)
        .widgetAccentable()
    }

    @ViewBuilder
    private func facts(_ stats: ScreenBreakStats) -> some View {
        WidgetFact(
            title: loc("Breaks today"),
            value: "\(stats.breaks.count) · \(WidgetDuration.short(stats.totalBreak))"
        )
        if let longest = stats.longestFocus {
            WidgetFact(title: loc("Longest focus"), value: WidgetDuration.short(longest.duration))
        }
        WidgetFact(title: loc("Average focus"), value: WidgetDuration.short(stats.averageFocus))
    }
}

/// One app, today and over the week. It follows the most used app until choosing one is possible.
struct AppTimeWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var log: ScreenTimeLog {
        context.snapshot.screenTime
    }

    private let symbol = "clock.fill"

    var body: some View {
        if let app = AppTimeStats.defaultApp(in: log, at: context.now) {
            let stats = AppTimeStats(app: app, log: log, at: context.now)
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 3) {
                    header
                    WidgetAppBadge(app: app, size: 24)
                    Text(WidgetDuration.short(stats.today)).font(.widgetFigure(24)).lineLimit(1)
                    Text(loc("\(app) today")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    change(stats)
                    Spacer(minLength: 0)
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        header
                        WidgetAppBadge(app: app, size: 24)
                        Text(WidgetDuration.short(stats.today)).font(.widgetFigure(26)).lineLimit(1)
                        Text(loc("\(app) today")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        change(stats)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetSection(title: loc("Last 7 days"))
                        ScreenWeekChart(days: stats.week, tint: Palette.blue, height: 96, hover: chartHover)
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 7) {
                    title(app)
                    summary(stats)
                    hours(stats)
                    Divider()
                    sessions(stats, limit: 3)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        title(app)
                        summary(stats)
                        hours(stats)
                        Divider()
                        sessions(stats, limit: 3)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetSection(title: loc("Last 7 days"))
                        ScreenWeekChart(days: stats.week, tint: Palette.blue, height: 150, hover: chartHover)
                        Divider()
                        WidgetFact(title: loc("This week"), value: WidgetDuration.short(stats.weekTotal))
                        WidgetFact(title: loc("Daily average"), value: WidgetDuration.short(stats.dailyAverage))
                        if let busiest = stats.busiest {
                            WidgetFact(
                                title: loc("Busiest day"),
                                value: "\(WidgetDuration.weekday(busiest.date)) · \(WidgetDuration.short(busiest.seconds))"
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: symbol, tint: Palette.blue, size: context.size)
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("App Time"), symbol: symbol, tint: Palette.blue)
    }

    private func title(_ app: String) -> some View {
        WidgetTitle(title: loc("App Time"), symbol: symbol, tint: Palette.blue, note: app)
    }

    private func summary(_ stats: AppTimeStats) -> some View {
        HStack(spacing: 10) {
            WidgetAppBadge(app: stats.app, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetDuration.short(stats.today)).font(.widgetFigure(26)).lineLimit(1)
                change(stats)
            }
        }
    }

    @ViewBuilder
    private func change(_ stats: AppTimeStats) -> some View {
        if let change = stats.change {
            WidgetChange(change: change, text: loc("\(Format.percent(abs(change))) vs average"))
        }
    }

    private func hours(_ stats: AppTimeStats) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetSection(title: loc("Today by hour"))
            ScreenHourChart(sessions: stats.sessions.reversed(), tint: Palette.blue, height: 60)
        }
    }

    @ViewBuilder
    private func sessions(_ stats: AppTimeStats, limit: Int) -> some View {
        WidgetSection(title: loc("Sessions"))
        ForEach(stats.sessions.prefix(limit), id: \.start) { session in
            WidgetFact(
                title: WidgetDuration.range(session.start, session.end),
                value: WidgetDuration.short(session.duration)
            )
        }
    }
}
