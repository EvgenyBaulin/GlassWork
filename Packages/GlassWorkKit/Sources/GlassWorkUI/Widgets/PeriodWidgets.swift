import GlassWorkCore
import SwiftUI

private extension PeriodProgress.Period {
    var title: String {
        switch self {
        case .day: loc("Today")
        case .week: loc("This week")
        case .month: loc("This month")
        case .quarter: loc("This quarter")
        case .year: loc("This year")
        }
    }

    var tint: Color {
        switch self {
        case .day: Palette.orange
        case .week: Palette.purple
        case .month: Palette.blue
        case .quarter: Palette.teal
        case .year: Palette.green
        }
    }
}

/// Day, week, month, quarter and year as rows of dots.
struct ProgressWidget: View {
    let context: TimeContext

    private func progress(_ period: PeriodProgress.Period) -> PeriodProgress {
        PeriodProgress(period, at: context.now)
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(spacing: 4) {
                ring(progress(.day), diameter: 104)
                Text(PeriodProgress.Period.day.title).font(.system(size: 13, weight: .semibold))
                Text(leftText(progress(.day))).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            VStack(spacing: 12) {
                ForEach([PeriodProgress.Period.day, .week, .year], id: \.self) { period in
                    row(progress(period), showsLeft: false)
                }
            }
            .frame(maxHeight: .infinity)
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                WidgetCapsTitle(title: loc("Progress"), tint: Palette.orange)
                rows
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetCapsTitle(title: loc("Progress"), tint: Palette.orange)
                    rows
                    Spacer(minLength: 0)
                }
                Divider()
                months.frame(width: 340)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 13) {
            ForEach(PeriodProgress.Period.allCases, id: \.self) { period in
                row(progress(period), showsLeft: true)
            }
        }
    }

    private func ring(_ item: PeriodProgress, diameter: CGFloat) -> some View {
        RingGauge(value: item.share, tint: item.period.tint, lineWidth: diameter / 9) {
            VStack(spacing: 0) {
                Text(Format.percent(item.share)).font(.widgetFigure(diameter / 4)).monospacedDigit()
                Text(loc("of today")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func row(_ item: PeriodProgress, showsLeft: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.period.title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(Format.percent(item.share))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(item.period.tint)
                    .monospacedDigit()
                    .widgetAccentable()
            }
            WidgetDotBar(value: item.share, tint: item.period.tint)
            if showsLeft {
                Text(leftText(item)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func leftText(_ item: PeriodProgress) -> String {
        if item.period == .day {
            return loc("\(CompactDuration.format(item.end.timeIntervalSince(context.now))) left")
        }
        return item.daysLeft == 0 ? loc("Last day") : loc("Days left: \(item.daysLeft)")
    }

    /// Twelve columns: full for months that are over, partly full for this one.
    private var months: some View {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: context.now)
        let share = progress(.month).share
        return VStack(alignment: .leading, spacing: 8) {
            WidgetSection(title: loc("Year by month"))
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(1 ... 12, id: \.self) { index in
                    let fill = index < month ? 1 : index == month ? share : 0
                    VStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Palette.green)
                                    .frame(height: geometry.size.height * fill)
                            }
                        }
                        Text(calendar.veryShortStandaloneMonthSymbols[index - 1])
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 130)
            .widgetAccentable()
            Spacer(minLength: 0)
        }
    }
}

/// Days to the weekend, or what is left of it.
struct WeekendWidget: View {
    let context: TimeContext

    private var weekend: WeekendCountdown {
        WeekendCountdown(at: context.now)
    }

    private var tint: Color {
        weekend.isWeekend ? Palette.green : Palette.purple
    }

    var body: some View {
        let state = weekend
        switch context.size {
        case .small:
            countdown(state)
        case .medium:
            HStack(spacing: 14) {
                countdown(state)
                Divider()
                workWeek(state)
            }
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    countdown(state)
                    Divider()
                    workWeek(state)
                }
                .frame(height: 142)
                Divider()
                plans(state, limit: 3)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        countdown(state)
                        Divider()
                        workWeek(state)
                    }
                    .frame(height: 142)
                    Divider()
                    weekStrip
                    Spacer(minLength: 0)
                }
                .frame(width: 370)
                Divider()
                plans(state, limit: 5)
            }
        }
    }

    private func countdown(_ state: WeekendCountdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetCapsTitle(title: loc("Weekend"), tint: tint)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(state.isWeekend ? loc("Now!") : figure(state).number)
                    .font(.widgetFigure(state.isWeekend ? 34 : 46))
                    .foregroundStyle(state.isWeekend ? tint : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if !state.isWeekend {
                    Text(figure(state).unit).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                }
            }
            Text(caption(state)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            dayDots
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One string, so the unit agrees with the number, drawn in two sizes.
    private func figure(_ state: WeekendCountdown) -> (number: String, unit: String) {
        let parts = loc("\(state.daysUntil) days away").split(separator: " ", maxSplits: 1).map(String.init)
        return (parts.first ?? "\(state.daysUntil)", parts.dropFirst().first ?? "")
    }

    private func caption(_ state: WeekendCountdown) -> String {
        let time = CompactDuration.format(state.remaining)
        guard !state.isWeekend else { return loc("\(time) left") }
        return loc("\(time) · until \(state.weekend.start.formatted(.dateTime.weekday(.abbreviated)))")
    }

    /// One dot per day of this week: today ringed, weekend days filled.
    private var dayDots: some View {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: context.now)?.start ?? context.now
        return HStack(spacing: 4) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: week) ?? week
                let isToday = calendar.isDate(day, inSameDayAs: context.now)
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .background(
                        calendar.isDateInWeekend(day) ? AnyShapeStyle(Palette.purple) : AnyShapeStyle(.quaternary),
                        in: .circle
                    )
                    .overlay(Circle().strokeBorder(isToday ? Color.primary : .clear, lineWidth: 1.5))
            }
        }
        .widgetAccentable()
    }

    private func workWeek(_ state: WeekendCountdown) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetSection(title: state.isWeekend ? loc("Weekend") : loc("Work week"))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.percent(state.progress)).font(.widgetFigure(20)).monospacedDigit()
                Text(loc("done")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            WidgetDotBar(value: state.progress, tint: Palette.purple, count: 20)
            Text(loc("\(CompactDuration.format(state.remaining)) left"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(range(state.weekend)).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func range(_ interval: DateInterval) -> String {
        let last = interval.end.addingTimeInterval(-1)
        let style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        return "\(interval.start.formatted(style)) – \(last.formatted(style))"
    }

    /// Calendar events during the weekend, then the weekends after it.
    private func plans(_ state: WeekendCountdown, limit: Int) -> some View {
        let events = context.snapshot.events.filter { state.weekend.contains($0.start) }
        return VStack(alignment: .leading, spacing: 8) {
            WidgetSection(title: loc("This weekend"))
            if events.isEmpty {
                Text(loc("No events yet")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(events.prefix(limit)) { event in
                HStack(spacing: 8) {
                    Capsule().fill(tint).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(event.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            InfoRow(title: state.isWeekend ? loc("Now") : loc("Next weekend"), value: range(state.weekend))
            if let following = state.following {
                InfoRow(title: loc("After that"), value: range(following))
            }
        }
    }

    /// The next seven days, weekend days filled and today ringed.
    private var weekStrip: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: context.now)
        return HStack(spacing: 6) {
            ForEach(0 ..< 7, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
                let isWeekend = calendar.isDateInWeekend(day)
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 30, height: 30)
                        .background(
                            isWeekend ? Palette.purple.opacity(0.85) : Color.primary.opacity(0.08),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(offset == 0 ? Color.primary : .clear, lineWidth: 1.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// The stopwatch kept by the Stopwatch module, as a large time.
struct StopwatchWidget: View {
    let context: TimeContext

    private var stopwatch: Stopwatch {
        context.snapshot.everyday.stopwatch
    }

    private var elapsed: TimeInterval {
        stopwatch.elapsed(at: context.now)
    }

    private var tint: Color {
        stopwatch.isRunning ? Palette.green : elapsed > 0 ? Palette.orange : Palette.gray
    }

    private var state: String {
        stopwatch.isRunning ? loc("Running") : elapsed > 0 ? loc("Paused") : loc("Ready")
    }

    private var status: some View {
        Text(statusText).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }

    /// "Running since 4:08 PM", or just the state.
    private var statusText: String {
        guard let started = stopwatch.startedAt else { return state }
        return loc("Running since \(started.formatted(date: .omitted, time: .shortened))")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: context.size == .small ? 6 : 8) {
            WidgetCapsTitle(title: loc("Stopwatch"), tint: Palette.green)
            time(size: figureSize)
            status
            Spacer(minLength: 0)
            hint
        }
    }

    private var figureSize: CGFloat {
        switch context.size {
        case .small: 34
        case .medium: 44
        case .large: 62
        case .extraLarge: 84
        }
    }

    /// A click opens the Timers panel, where the controls are.
    private var hint: some View {
        Text(loc("Click to open Timers")).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
    }

    /// In WidgetKit a running stopwatch counts on its own between refreshes; GlassWork's own windows redraw each
    /// second.
    private func time(size: CGFloat) -> some View {
        Group {
            if let startedAt = stopwatch.startedAt, !context.showsSeconds {
                Text(
                    timerInterval: startedAt.addingTimeInterval(-stopwatch.accumulated) ... .distantFuture,
                    countsDown: false
                )
            } else {
                Text(elapsed.elapsedText)
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}
