import GlassWorkCore
import SwiftUI

extension ChartSeries {
    /// One value per day on the shared interactive chart.
    static func daily(
        id: String,
        title: String,
        color: Color,
        values: [(date: Date, value: Double)],
        format: @escaping (Double) -> String
    ) -> ChartSeries {
        var history = History<Double>(capacity: max(values.count, 1))
        for item in values {
            history.append(item.value, at: item.date)
        }
        return ChartSeries(id: id, title: title, color: color, points: history.points, format: format)
    }
}

/// Focus and break rounds from the Timers panel.
struct PomodoroWidget: View {
    let context: TimeContext

    private var session: PomodoroSession {
        context.snapshot.everyday.pomodoro ?? PomodoroSession()
    }

    private var state: PomodoroState? {
        session.state(at: context.now)
    }

    private var tint: Color {
        guard let state else { return Palette.gray }
        return state.phase.isBreak ? Palette.green : Palette.red
    }

    private var phaseTitle: String {
        guard let state else { return loc("Not started") }
        switch state.phase {
        case .focus: return loc("Focus")
        case .shortBreak: return loc("Short break")
        case .longBreak: return loc("Long break")
        }
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(spacing: 6) {
                WidgetHeader(title: phaseTitle, symbol: "timer", tint: tint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ring(diameter: 96)
                dots
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            HStack(spacing: 16) {
                ring(diameter: 120)
                summary
            }
        case .large:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ring(diameter: 120)
                    summary
                }
                Divider()
                schedule(limit: 3)
                history(days: 7)
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        ring(diameter: 130)
                        summary
                    }
                    Divider()
                    schedule(limit: 4)
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    history(days: 7, height: 190)
                    Spacer(minLength: 0)
                }
                .frame(width: 330)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(phaseTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .widgetAccentable()
            if let state {
                Text(loc("Ends \(state.phaseEnd.formatted(date: .omitted, time: .shortened))"))
                    .font(.system(size: 13))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    dots
                    Text(loc("Session \(state.round) of \(max(session.roundsPerSet, 1))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let next = session.upcoming(1, at: context.now).first {
                    Text(loc("Next: \(nextTitle(next))"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(loc("Rounds today: \(session.completedToday(at: context.now))"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func nextTitle(_ next: PomodoroState) -> String {
        let minutes = Int((next.duration / 60).rounded())
        return next.phase.isBreak ? loc("\(minutes) min break") : loc("\(minutes) min focus")
    }

    /// One dot per round of the set, filled up to the one under way.
    private var dots: some View {
        let total = max(session.roundsPerSet, 1)
        let current = state?.round ?? 0
        return HStack(spacing: 5) {
            ForEach(1 ... total, id: \.self) { round in
                Circle()
                    .fill(round <= current ? Palette.red : Color.primary.opacity(0.15))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func ring(diameter: CGFloat) -> some View {
        RingGauge(value: state.map { 1 - $0.share(at: context.now) } ?? 0, tint: tint, lineWidth: diameter / 10) {
            if let state {
                countdown(state)
                    .font(.system(size: diameter / 4.4, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Image(systemName: "play.fill").font(.system(size: diameter / 4)).foregroundStyle(tint)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// In WidgetKit the countdown runs on its own. Snapshots draw a fixed time.
    @ViewBuilder
    private func countdown(_ state: PomodoroState) -> some View {
        if context.showsSeconds {
            Text(state.remaining(at: context.now).clockText)
        } else {
            Text(timerInterval: context.now ... max(state.phaseEnd, context.now), countsDown: true)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func schedule(limit: Int) -> some View {
        let upcoming = session.upcoming(limit, at: context.now)
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Next")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if upcoming.isEmpty {
                Text(loc("Start a Pomodoro in the Timers panel")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(Array(upcoming.enumerated()), id: \.offset) { _, item in
                HStack {
                    Circle().fill(item.phase.isBreak ? Palette.green : Palette.red).frame(width: 8, height: 8)
                    Text(item.phase == .focus ? loc("Focus") : loc("Break")).font(.system(size: 13))
                    Spacer()
                    Text(item.phaseStart.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func history(days: Int, height: CGFloat = 70) -> some View {
        let recent = session.recentDays(days, at: context.now)
        return VStack(alignment: .leading, spacing: 4) {
            WidgetSection(title: loc("Last 7 days"))
            InteractiveChart(
                series: [.daily(
                    id: "rounds",
                    title: loc("Rounds"),
                    color: Palette.red,
                    values: recent.map { ($0.date, Double($0.count)) }
                ) { "\(Int($0))" }],
                domain: 0 ... max(Double(recent.map(\.count).max() ?? 0), 4),
                height: height,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .bars(unit: .day, width: 18)
            )
        }
    }
}

/// Active time today against yesterday and the week, from the Screen Time log.
struct FocusTimeWidget: View {
    let context: TimeContext

    private var stats: FocusStats {
        FocusStats(log: context.snapshot.screenTime, at: context.now)
    }

    var body: some View {
        let stats = stats
        if !stats.hasData {
            empty
        } else {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Spacer()
                    total(stats, size: 40)
                    comparison(stats)
                }
            case .medium:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        header
                        total(stats, size: 38)
                        comparison(stats)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        topApp(stats)
                        InfoRow(title: loc("Week average"), value: CompactDuration.format(stats.weekAverage))
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 12) {
                    header
                    HStack {
                        total(stats, size: 38)
                        Spacer()
                        comparison(stats)
                    }
                    weekChart(stats)
                    topApp(stats)
                    InfoRow(title: loc("Yesterday"), value: CompactDuration.format(stats.yesterday))
                    InfoRow(title: loc("Week average"), value: CompactDuration.format(stats.weekAverage))
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        total(stats, size: 56)
                        comparison(stats)
                        Divider()
                        topApp(stats)
                        InfoRow(title: loc("Yesterday"), value: CompactDuration.format(stats.yesterday))
                        InfoRow(title: loc("Week average"), value: CompactDuration.format(stats.weekAverage))
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        weekChart(stats)
                        apps
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var header: some View {
        WidgetCapsTitle(title: loc("Focus Time"), tint: Palette.purple)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer()
            Text(loc("No data yet")).font(.system(size: 15, weight: .semibold))
            Text(loc("Turn on Screen Time tracking in Settings to see your focus."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func total(_ stats: FocusStats, size: CGFloat) -> some View {
        Text(CompactDuration.format(stats.today))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }

    private func comparison(_ stats: FocusStats) -> some View {
        let delta = stats.today - stats.yesterday
        let text = CompactDuration.format(abs(delta))
        return Group {
            if stats.yesterday == 0 {
                Text(loc("active today"))
            } else if delta >= 0 {
                Text(loc("+\(text) vs yesterday"))
            } else {
                Text(loc("−\(text) vs yesterday"))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func topApp(_ stats: FocusStats) -> some View {
        if let top = stats.topApp {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(top.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(Format.percent(top.share)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ThinBar(value: top.share, tint: Palette.purple, height: 6)
            }
        }
    }

    private func weekChart(_ stats: FocusStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetSection(title: loc("Last 7 days"))
            InteractiveChart(
                series: [.daily(
                    id: "focus",
                    title: loc("Active"),
                    color: Palette.purple,
                    values: stats.week.map { ($0.date, $0.seconds) }
                ) { CompactDuration.format($0) }],
                height: 80,
                tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted),
                style: .bars(unit: .day, width: 18)
            )
        }
    }

    @ViewBuilder
    private var apps: some View {
        let log = context.snapshot.screenTime
        if let day = log.today(context.now) {
            let top = log.topApps(in: day, limit: 5)
            let peak = max(top.first?.seconds ?? 1, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(loc("Apps today")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(top, id: \.app) { item in
                    HStack(spacing: 8) {
                        Text(item.app).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        ThinBar(value: item.seconds / peak, tint: Palette.purple).frame(width: 90)
                        Text(CompactDuration.format(item.seconds))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                }
            }
        }
    }
}
