import GlassWorkCore
import SwiftUI

/// The Screen Time card of the Dock: today, the last seven days, the apps used most and the breaks taken.
struct ScreenTimePanel: View {
    let log: ScreenTimeLog

    var body: some View {
        ScreenTimeCard(summary: ScreenTimeSummary(log: log, at: Date()))
    }
}

struct ScreenTimeCard: View {
    let summary: ScreenTimeSummary
    var chartHover: Date?

    var body: some View {
        DockCardFrame(module: .screenTime) {
            if summary.hasData {
                content
            } else {
                Text(loc("Turn on Screen Time tracking in Settings to see this."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(WidgetDuration.short(summary.today)).font(.widgetFigure(34)).lineLimit(1)
            Text(loc("active today")).font(.system(size: 11)).foregroundStyle(.secondary)
            if let change = summary.week.todayChange {
                WidgetChange(change: change, text: loc("\(Format.percent(abs(change))) vs average"))
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            WidgetSection(title: loc("Last 7 days"))
            ScreenWeekChart(
                days: summary.week.days,
                tint: Palette.purple,
                height: 86,
                reference: summary.week.dailyAverage,
                hover: chartHover
            )
        }
        Divider()
        VStack(alignment: .leading, spacing: 5) {
            WidgetSection(title: loc("Most used today"))
            ForEach(summary.topApps, id: \.name) { app in
                WidgetAppRow(
                    app: app.name,
                    seconds: app.seconds,
                    peak: summary.topApps.first?.seconds ?? 1,
                    tint: Palette.purple,
                    barWidth: 80
                )
            }
        }
        if summary.breaks.hasData {
            Divider()
            breaks(summary.breaks)
        }
    }

    private func breaks(_ stats: ScreenBreakStats) -> some View {
        VStack(spacing: 4) {
            WidgetFact(
                title: loc("Breaks today"),
                value: "\(stats.breaks.count) · \(WidgetDuration.short(stats.totalBreak))"
            )
            if let longest = stats.longestFocus {
                WidgetFact(title: loc("Longest focus"), value: WidgetDuration.short(longest.duration))
            }
            WidgetFact(title: loc("Since last break"), value: WidgetDuration.short(stats.sinceBreak))
        }
    }
}
