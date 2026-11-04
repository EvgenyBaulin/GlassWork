import GlassWorkCore
import SwiftUI
import WidgetKit

/// The date, the next event, the battery and how far the day has gone, in one place.
struct TodayWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    private var calendar: Calendar {
        .current
    }

    /// Events still to come. An event under way counts: it is what the day is about right now.
    private var upcoming: [AgendaEvent] {
        context.snapshot.events
            .filter { $0.end > now && !$0.isDeclined && !$0.isAllDay }
            .sorted { $0.start < $1.start }
    }

    private var today: [AgendaEvent] {
        upcoming.filter { calendar.isDate($0.start, inSameDayAs: now) }
    }

    private var tomorrow: [AgendaEvent] {
        guard let date = calendar.date(byAdding: .day, value: 1, to: now) else { return [] }
        return upcoming.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    private var day: PeriodProgress {
        PeriodProgress(.day, at: now)
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                weekday
                date(size: 20)
                Text(ClockPlace.local.timeText(at: now))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                nextEvent(detail: false)
                Spacer(minLength: 0)
                dayBar
            }
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                header
                nextEvent(detail: true)
                Spacer(minLength: 0)
                vitals
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                header
                nextEvent(detail: true)
                vitals
                Divider()
                periods
                footer
                Spacer(minLength: 0)
                laterToday
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    header
                    nextEvent(detail: true)
                    vitals
                    Divider()
                    periods
                    Spacer(minLength: 0)
                    footer
                }
                Divider()
                agenda.frame(width: 340)
            }
        }
    }

    private var weekday: some View {
        Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.red)
            .lineLimit(1)
            .widgetAccentable()
    }

    private func date(size: CGFloat) -> some View {
        Text(now.formatted(.dateTime.month(.wide).day()))
            .font(.system(size: size, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                weekday
                date(size: 28)
            }
            Spacer(minLength: 8)
            Text(ClockPlace.local.timeText(at: now))
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func wait(until event: AgendaEvent) -> String {
        guard event.start > now else { return loc("Now") }
        return loc("in \(CompactDuration.format(event.start.timeIntervalSince(now)))")
    }

    @ViewBuilder
    private func nextEvent(detail: Bool) -> some View {
        if let event = upcoming.first {
            HStack(spacing: 7) {
                Capsule().fill(Color(hex: event.calendarColor)).frame(width: 3, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if detail {
                        Text(
                            verbatim: "\(wait(until: event)) · \(event.start.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    } else {
                        Text(wait(until: event))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.red)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                }
            }
        } else {
            Text(loc("No more events today")).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var dayBar: some View {
        VStack(spacing: 3) {
            HStack {
                Text(loc("Day")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(day.share)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            ThinBar(value: day.share, tint: Palette.orange)
        }
    }

    private var vitals: some View {
        HStack(spacing: 18) {
            if let battery = context.snapshot.battery {
                HStack(spacing: 7) {
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.green)
                        .widgetAccentable()
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Format.percent(battery.charge)).font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                        Text(batteryState(battery)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            dayBar
        }
    }

    private func batteryState(_ battery: BatterySample) -> String {
        battery.isCharging ? loc("Charging") : battery.isOnAC ? loc("Power Adapter") : loc("On battery")
    }

    private var periods: some View {
        VStack(spacing: 10) {
            ForEach([PeriodProgress.Period.day, .week, .year], id: \.self) { period in
                let item = PeriodProgress(period, at: now)
                VStack(spacing: 4) {
                    HStack {
                        Text(title(period)).font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.percent(item.share))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint(period))
                            .monospacedDigit()
                    }
                    WidgetDotBar(value: item.share, tint: tint(period))
                }
            }
        }
    }

    private func title(_ period: PeriodProgress.Period) -> String {
        switch period {
        case .week: loc("This week")
        case .year: loc("This year")
        default: loc("Today")
        }
    }

    private func tint(_ period: PeriodProgress.Period) -> Color {
        switch period {
        case .week: Palette.purple
        case .year: Palette.green
        default: Palette.orange
        }
    }

    private var footer: some View {
        let week = calendar.component(.weekOfYear, from: now)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let left = PeriodProgress(.year, at: now).daysLeft
        return Text(verbatim: "\(loc("Week \(week)")) · \(loc("Day \(dayOfYear)")) · \(loc("Days left: \(left)"))")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var laterToday: some View {
        if today.count > 1 {
            VStack(alignment: .leading, spacing: 5) {
                WidgetSection(title: loc("Later today"))
                agendaRow(today[1], showsTime: false)
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetSection(title: loc("Today"))
            if today.isEmpty {
                Text(loc("No more events today")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(today.prefix(3)) { agendaRow($0, showsTime: true) }
            Divider()
            WidgetSection(title: loc("Tomorrow"))
            if tomorrow.isEmpty {
                Text(loc("No events tomorrow")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(tomorrow.prefix(3)) { agendaRow($0, showsTime: true) }
            Spacer(minLength: 0)
        }
    }

    private func agendaRow(_ event: AgendaEvent, showsTime: Bool) -> some View {
        HStack(spacing: 8) {
            if showsTime {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 62, alignment: .leading)
                    .lineLimit(1)
            }
            Capsule().fill(Color(hex: event.calendarColor)).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(WidgetDuration.short(event.end.timeIntervalSince(event.start)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let url = event.callURL {
                Link(destination: url) {
                    Text(loc("Join"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .widgetSolid(Palette.blue, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
