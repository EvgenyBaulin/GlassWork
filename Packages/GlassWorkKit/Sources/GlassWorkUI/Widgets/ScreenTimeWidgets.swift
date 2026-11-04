import GlassWorkCore
import SwiftUI
import WidgetKit

extension AppCategory {
    var title: String {
        switch self {
        case .development: loc("Development")
        case .productivity: loc("Productivity")
        case .communication: loc("Communication")
        case .entertainment: loc("Entertainment")
        case .other: loc("Other")
        }
    }

    var tint: Color {
        switch self {
        case .development: Palette.blue
        case .productivity: Palette.green
        case .communication: Palette.purple
        case .entertainment: Palette.pink
        case .other: Palette.gray
        }
    }
}

/// The message every Screen Time widget shows before tracking has anything to tell.
struct ScreenTimeEmpty: View {
    let symbol: String
    let tint: Color
    let size: WidgetSize

    var body: some View {
        WidgetEmptyState(
            symbol: symbol,
            title: loc("Not enough data yet"),
            detail: size == .small ? nil : loc("Turn on Screen Time tracking in Settings to see this."),
            tint: tint
        )
    }
}

/// Today's time by hour, as bars on the shared chart.
struct ScreenHourChart: View {
    let sessions: [ScreenSession]
    let tint: Color
    let height: CGFloat
    var hover: Date?

    private var hours: [(hour: Date, seconds: Double)] {
        ScreenHours.today(sessions)
    }

    var body: some View {
        let hours = hours
        VStack(spacing: 2) {
            InteractiveChart(
                series: [ChartSeries(
                    id: "hours",
                    title: loc("Active"),
                    color: tint,
                    points: hours.map { History<Double>.Point(date: $0.hour, value: $0.seconds) },
                    format: { WidgetDuration.short($0) }
                )],
                height: height,
                tooltipDate: Date.FormatStyle(date: .omitted, time: .shortened),
                style: .bars(unit: .hour),
                initialHover: hover
            )
            if let first = hours.first, let last = hours.last {
                HStack {
                    Text(WidgetDuration.clock(first.hour))
                    Spacer()
                    Text(WidgetDuration.clock(last.hour))
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// Seven days as bars, today in full color and the rest toned down, with labels below.
struct ScreenWeekChart: View {
    let days: [ScreenWeekStats.Day]
    let tint: Color
    let height: CGFloat
    var reference: Double?
    var hover: Date?

    var body: some View {
        VStack(spacing: 2) {
            InteractiveChart(
                series: [ChartSeries(
                    id: "week",
                    title: loc("Active"),
                    color: tint,
                    points: days.map { History<Double>.Point(date: $0.date, value: $0.seconds) },
                    format: { WidgetDuration.short($0) }
                )],
                height: height,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .bars(unit: .day),
                reference: reference,
                emphasized: days.last?.date,
                initialHover: hover
            )
            WidgetAxisLabels(labels: days.map { WidgetDuration.weekday($0.date) })
        }
    }
}

/// Today so far, against the days before it.
struct ScreenTimeWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var log: ScreenTimeLog {
        context.snapshot.screenTime
    }

    private var day: ScreenDay? {
        log.today(context.now)
    }

    private var week: ScreenWeekStats {
        ScreenWeekStats(log: log, at: context.now)
    }

    private var categories: ScreenCategoryStats {
        ScreenCategoryStats(day: day, categories: log.categories)
    }

    var body: some View {
        if let day, day.total > 0 {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 2) {
                    header
                    figure(day, size: 26)
                    Text(loc("today")).font(.system(size: 11)).foregroundStyle(.secondary)
                    change
                    Spacer(minLength: 0)
                    hours(height: 36)
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        header
                        figure(day, size: 30)
                        change
                        Spacer(minLength: 0)
                        categoryBar
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 3) {
                        WidgetSection(title: loc("Today by hour"))
                        hours(height: 92)
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 7) {
                    title
                    figure(day, size: 34)
                    change
                    hours(height: 78)
                    Divider()
                    apps(day, limit: 3)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        title
                        figure(day, size: 34)
                        change
                        WidgetSection(title: loc("By hour"))
                        hours(height: 78)
                        WidgetSection(title: loc("Categories"))
                        categoryBar
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetSection(title: loc("Last 7 days"))
                        ScreenWeekChart(
                            days: week.days,
                            tint: Palette.purple,
                            height: 112,
                            reference: week.dailyAverage,
                            hover: chartHover
                        )
                        Divider()
                        apps(day, limit: 4)
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: "hourglass", tint: Palette.purple, size: context.size)
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Screen Time"), symbol: "hourglass", tint: Palette.purple)
    }

    private var title: some View {
        WidgetTitle(title: loc("Screen Time"), symbol: "hourglass", tint: Palette.purple, note: loc("Today"))
    }

    private func figure(_ day: ScreenDay, size: CGFloat) -> some View {
        Text(WidgetDuration.short(day.total)).font(.widgetFigure(size)).lineLimit(1).minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var change: some View {
        if let change = week.todayChange {
            WidgetChange(change: change, text: loc("\(Format.percent(abs(change))) vs average"))
        }
    }

    private func hours(height: CGFloat) -> some View {
        ScreenHourChart(sessions: day?.sessions ?? [], tint: Palette.purple, height: height)
    }

    /// The day split by category, the widest first.
    private var categoryBar: some View {
        let rows = categories.rows
        return GeometryReader { geometry in
            let room = geometry.size.width - CGFloat(max(rows.count - 1, 0)) * 2
            HStack(spacing: 2) {
                ForEach(rows) { row in
                    Capsule()
                        .fill(row.category.tint)
                        .frame(width: max(room * row.share, 3))
                        .help("\(row.category.title) · \(WidgetDuration.short(row.seconds))")
                }
            }
        }
        .frame(height: 5)
        .widgetAccentable()
    }

    @ViewBuilder
    private func apps(_ day: ScreenDay, limit: Int) -> some View {
        let top = log.topApps(in: day, limit: limit)
        WidgetSection(title: loc("Most used today"))
        ForEach(top, id: \.app) { item in
            WidgetAppRow(app: item.app, seconds: item.seconds, peak: top.first?.seconds ?? 1, tint: Palette.purple)
        }
    }
}

/// The last seven days, with what stood out.
struct ScreenTimeWeekWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var week: ScreenWeekStats {
        ScreenWeekStats(log: context.snapshot.screenTime, at: context.now)
    }

    private let symbol = "chart.bar.fill"

    var body: some View {
        let week = week
        if week.hasData {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 2) {
                    header
                    Text(WidgetDuration.short(week.dailyAverage)).font(.widgetFigure(26)).lineLimit(1)
                    Text(loc("daily average")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    chart(week, height: 44, labelled: false)
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        header
                        Text(WidgetDuration.short(week.total)).font(.widgetFigure(28)).lineLimit(1)
                        Text(loc("last 7 days")).font(.system(size: 11)).foregroundStyle(.secondary)
                        change(week)
                        Spacer(minLength: 0)
                        Text(loc("Avg \(WidgetDuration.short(week.dailyAverage)) a day"))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    chart(week, height: 104, labelled: true)
                }
            case .large:
                VStack(alignment: .leading, spacing: 7) {
                    title
                    Text(WidgetDuration.short(week.total)).font(.widgetFigure(34))
                    change(week)
                    chart(week, height: 130, labelled: true)
                    Divider()
                    facts(week)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        title
                        Text(WidgetDuration.short(week.total)).font(.widgetFigure(34))
                        change(week)
                        facts(week)
                        WidgetFact(title: loc("Weekdays"), value: WidgetDuration.short(week.average(weekend: false)))
                        WidgetFact(title: loc("Weekend"), value: WidgetDuration.short(week.average(weekend: true)))
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetSection(title: loc("This week vs previous week"))
                        comparison(week)
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: symbol, tint: Palette.purple, size: context.size)
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Week"), symbol: symbol, tint: Palette.purple)
    }

    private var title: some View {
        WidgetTitle(title: loc("Screen Time Week"), symbol: symbol, tint: Palette.purple, note: loc("Last 7 days"))
    }

    @ViewBuilder
    private func change(_ week: ScreenWeekStats) -> some View {
        if let change = week.weekChange {
            WidgetChange(change: change, text: loc("\(Format.percent(abs(change))) vs previous 7 days"))
        }
    }

    @ViewBuilder
    private func chart(_ week: ScreenWeekStats, height: CGFloat, labelled: Bool) -> some View {
        if labelled {
            ScreenWeekChart(
                days: week.days,
                tint: Palette.purple,
                height: height,
                reference: week.dailyAverage,
                hover: chartHover
            )
        } else {
            InteractiveChart(
                series: [ChartSeries(
                    id: "week",
                    title: loc("Active"),
                    color: Palette.purple,
                    points: week.days.map { History<Double>.Point(date: $0.date, value: $0.seconds) },
                    format: { WidgetDuration.short($0) }
                )],
                height: height,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .bars(unit: .day),
                reference: week.dailyAverage,
                emphasized: week.days.last?.date
            )
        }
    }

    @ViewBuilder
    private func facts(_ week: ScreenWeekStats) -> some View {
        WidgetFact(title: loc("Daily average"), value: WidgetDuration.short(week.dailyAverage))
        if let busiest = week.busiest {
            WidgetFact(title: loc("Busiest day"), value: dayText(busiest))
        }
        if let quietest = week.quietest {
            WidgetFact(title: loc("Quietest day"), value: dayText(quietest))
        }
    }

    private func dayText(_ day: ScreenWeekStats.Day) -> String {
        "\(WidgetDuration.weekday(day.date)) · \(WidgetDuration.short(day.seconds))"
    }

    /// Previous week's day next to this week's, joined on the position in the week.
    private func comparison(_ week: ScreenWeekStats) -> some View {
        let dates = week.days.map(\.date)
        let previous = zip(dates, week.previous).map { date, day in
            History<Double>.Point(date: date, value: day.seconds)
        }
        return VStack(spacing: 4) {
            InteractiveChart(
                series: [
                    ChartSeries(
                        id: "previous",
                        title: loc("Previous"),
                        color: Palette.gray,
                        points: previous,
                        format: { WidgetDuration.short($0) }
                    ),
                    ChartSeries(
                        id: "current",
                        title: loc("Last 7 days"),
                        color: Palette.purple,
                        points: week.days.map { History<Double>.Point(date: $0.date, value: $0.seconds) },
                        format: { WidgetDuration.short($0) }
                    ),
                ],
                height: 180,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .groupedBars(unit: .day),
                initialHover: chartHover
            )
            WidgetAxisLabels(labels: week.days.map { WidgetDuration.weekday($0.date) })
            HStack(spacing: 12) {
                legend(loc("Last 7 days · \(WidgetDuration.short(week.total))"), Palette.purple)
                legend(loc("Previous · \(WidgetDuration.short(week.previousTotal))"), Palette.gray)
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// The most used apps today and over the week.
struct MostUsedWidget: View {
    let context: TimeContext

    private var log: ScreenTimeLog {
        context.snapshot.screenTime
    }

    private var today: [(app: String, seconds: Double)] {
        log.topApps(days: 1, limit: 8, at: context.now)
    }

    private var week: [(app: String, seconds: Double)] {
        log.topApps(days: 7, limit: 8, at: context.now)
    }

    private let symbol = "star.fill"

    var body: some View {
        let today = today
        if let top = today.first {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 5) {
                    header
                    HStack(spacing: 8) {
                        WidgetAppBadge(app: top.app, size: 30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(top.app).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(WidgetDuration.short(top.seconds)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    ForEach(today.dropFirst().prefix(2), id: \.app) { item in
                        HStack(spacing: 5) {
                            WidgetAppBadge(app: item.app, size: 14)
                            Text(item.app).font(.system(size: 11)).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(WidgetDuration.short(item.seconds)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            case .medium:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    HStack(alignment: .top) {
                        ForEach(today.prefix(3), id: \.app) { item in
                            VStack(spacing: 3) {
                                WidgetAppBadge(app: item.app, size: 40)
                                Text(item.app).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Text(WidgetDuration.short(item.seconds)).font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    title(today)
                    list(today)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        title(today)
                        WidgetSection(title: loc("Today"))
                        list(today, barWidth: 110)
                        Spacer(minLength: 0)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 7) {
                        WidgetSection(title: loc("Last 7 days"))
                        list(week, barWidth: 110)
                        Spacer(minLength: 0)
                    }
                }
            }
        } else {
            ScreenTimeEmpty(symbol: symbol, tint: Palette.orange, size: context.size)
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Most Used"), symbol: symbol, tint: Palette.orange)
    }

    private func title(_ apps: [(app: String, seconds: Double)]) -> some View {
        let total = apps.map(\.seconds).reduce(0, +)
        return WidgetTitle(
            title: loc("Most Used"),
            symbol: symbol,
            tint: Palette.orange,
            note: loc("Today · \(WidgetDuration.short(total))")
        )
    }

    private func list(_ apps: [(app: String, seconds: Double)], barWidth: CGFloat = 90) -> some View {
        VStack(spacing: 8) {
            ForEach(apps, id: \.app) { item in
                WidgetAppRow(
                    app: item.app,
                    seconds: item.seconds,
                    peak: apps.first?.seconds ?? 1,
                    tint: Palette.orange,
                    barWidth: barWidth
                )
            }
        }
    }
}
