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

/// Day, week, month and year as bars and rings.
struct ProgressWidget: View {
    let context: TimeContext

    private func progress(_ period: PeriodProgress.Period) -> PeriodProgress {
        PeriodProgress(period, at: context.now)
    }

    var body: some View {
        switch context.size {
        case .small:
            ring(progress(.year), diameter: 120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            VStack(spacing: 10) {
                ForEach([PeriodProgress.Period.day, .week, .month, .year], id: \.self) { period in
                    bar(progress(period))
                }
            }
            .frame(maxHeight: .infinity)
        case .large:
            VStack(alignment: .leading, spacing: 14) {
                header
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach([PeriodProgress.Period.day, .week, .month, .year], id: \.self) { period in
                        ring(progress(period), diameter: 120)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach([PeriodProgress.Period.day, .week, .month, .year], id: \.self) { period in
                            ring(progress(period), diameter: 110)
                        }
                    }
                }
                VStack(spacing: 14) {
                    ForEach(PeriodProgress.Period.allCases, id: \.self) { period in
                        detail(progress(period))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Progress"), symbol: "chart.bar.fill", tint: Palette.green)
    }

    private func ring(_ item: PeriodProgress, diameter: CGFloat) -> some View {
        VStack(spacing: 6) {
            RingGauge(value: item.share, tint: item.period.tint, lineWidth: diameter / 9) {
                VStack(spacing: 0) {
                    Text(Format.percent(item.share))
                        .font(.system(size: diameter / 5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if context.size == .small {
                        Text(daysLeftText(item)).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            if context.size != .small {
                Text(item.period.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private func bar(_ item: PeriodProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.period.title).foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(item.share)).foregroundStyle(item.period.tint).monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium))
            ThinBar(value: item.share, tint: item.period.tint, height: 6)
        }
    }

    private func detail(_ item: PeriodProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            bar(item)
            Text(daysLeftText(item)).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func daysLeftText(_ item: PeriodProgress) -> String {
        item.daysLeft == 0 ? loc("Last day") : loc("Days left: \(item.daysLeft)")
    }
}

/// Days to the weekend, or what is left of it.
struct WeekendWidget: View {
    let context: TimeContext

    private var weekend: WeekendCountdown {
        WeekendCountdown(at: context.now)
    }

    var body: some View {
        let state = weekend
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer()
                headline(state, size: 46)
                Text(caption(state)).font(.system(size: 13)).foregroundStyle(.secondary)
                ThinBar(value: state.progress, tint: Palette.orange, height: 6)
            }
        case .medium:
            HStack(spacing: 16) {
                ring(state, diameter: 112)
                VStack(alignment: .leading, spacing: 4) {
                    header
                    headline(state, size: 30)
                    Text(caption(state)).font(.system(size: 13)).foregroundStyle(.secondary)
                    Text(range(state.weekend)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ring(state, diameter: 120)
                    VStack(alignment: .leading, spacing: 4) {
                        header
                        headline(state, size: 34)
                        Text(caption(state)).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                weekStrip
                weekendRows(state)
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ring(state, diameter: 170)
                    headline(state, size: 34)
                    Text(caption(state)).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    weekStrip
                    weekendRows(state)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Weekend"), symbol: "beach.umbrella", tint: Palette.orange)
    }

    private func headline(_ state: WeekendCountdown, size: CGFloat) -> some View {
        Text(state.isWeekend ? loc("Weekend!") : "\(state.daysUntil)")
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func caption(_ state: WeekendCountdown) -> String {
        if state.isWeekend {
            return loc("\(CompactDuration.format(state.remaining)) left")
        }
        return state.daysUntil == 1 ? loc("day to go") : loc("days to go")
    }

    private func ring(_ state: WeekendCountdown, diameter: CGFloat) -> some View {
        RingGauge(value: state.progress, tint: Palette.orange, lineWidth: diameter / 10) {
            Image(systemName: state.isWeekend ? "party.popper" : "briefcase")
                .font(.system(size: diameter / 3))
                .foregroundStyle(Palette.orange)
        }
        .frame(width: diameter, height: diameter)
    }

    private func range(_ interval: DateInterval) -> String {
        let last = interval.end.addingTimeInterval(-1)
        let style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        return "\(interval.start.formatted(style)) – \(last.formatted(style))"
    }

    /// The next seven days, weekend days in orange and today ringed.
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
                            isWeekend ? Palette.orange.opacity(0.85) : Color.primary.opacity(0.08),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(offset == 0 ? Color.primary : .clear, lineWidth: 1.5))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekendRows(_ state: WeekendCountdown) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InfoRow(title: state.isWeekend ? loc("Now") : loc("Next weekend"), value: range(state.weekend))
            if let following = state.following {
                InfoRow(title: loc("After that"), value: range(following))
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

    var body: some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                header
                Spacer()
                time(size: 40)
                Text(state).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
            }
        case .medium:
            HStack(spacing: 16) {
                ring(diameter: 120)
                VStack(alignment: .leading, spacing: 4) {
                    header
                    time(size: 38)
                    Text(state).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                    startedText
                }
            }
        case .large, .extraLarge:
            VStack(alignment: .leading, spacing: 14) {
                header
                ring(diameter: context.size == .large ? 190 : 230)
                    .frame(maxWidth: .infinity)
                time(size: context.size == .large ? 46 : 60)
                    .frame(maxWidth: .infinity)
                Divider()
                InfoRow(title: loc("Status"), value: state)
                InfoRow(title: loc("Elapsed"), value: elapsed.elapsedText)
                if let started = stopwatch.startedAt {
                    InfoRow(title: loc("Started"), value: started.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }

    private var header: some View {
        WidgetHeader(title: loc("Stopwatch"), symbol: "stopwatch", tint: Palette.orange)
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
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    @ViewBuilder
    private var startedText: some View {
        if let started = stopwatch.startedAt {
            Text(loc("Started \(started.formatted(date: .omitted, time: .shortened))"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    /// One turn is one minute.
    private func ring(diameter: CGFloat) -> some View {
        RingGauge(value: elapsed.truncatingRemainder(dividingBy: 60) / 60, tint: tint, lineWidth: diameter / 12) {
            Image(systemName: stopwatch.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: diameter / 4))
                .foregroundStyle(tint)
        }
        .frame(width: diameter, height: diameter)
    }
}
