import GlassWorkCore
import SwiftUI
import WidgetKit

/// Colored heading used across widgets.
struct WidgetHeader: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .widgetAccentable()
    }
}

struct ModularClockWidget: View {
    let size: WidgetSize
    let now: Date

    private var calendar: Calendar {
        .current
    }

    private var dayShare: Double {
        now.timeIntervalSince(calendar.startOfDay(for: now)) / 86400
    }

    private var weekShare: Double {
        let weekday = (calendar.component(.weekday, from: now) - calendar.firstWeekday + 7) % 7
        return (Double(weekday) + dayShare) / 7
    }

    private var yearShare: Double {
        let day = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let days = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        return Double(day) / Double(days)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(now.formatted(.dateTime.weekday().month().day()).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.orange)
                Text(now, style: .time)
                    .font(.system(size: size == .small ? 30 : 42, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                Spacer()
                Text(loc("Week \(calendar.component(.weekOfYear, from: now))"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if size != .small {
                VStack(spacing: 8) {
                    progress(loc("Today"), dayShare, Palette.orange)
                    progress(loc("This week"), weekShare, Palette.purple)
                    progress(loc("This year"), yearShare, Palette.green)
                }
            }
        }
    }

    private func progress(_ title: String, _ value: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(Format.percent(value)).foregroundStyle(tint).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            ThinBar(value: value, tint: tint)
        }
    }
}

struct CalendarMonthWidget: View {
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(now.formatted(.dateTime.month(.wide)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.red)
            MonthGrid(month: now)
        }
    }
}

struct UpNextWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    let now: Date

    private var upcoming: [AgendaEvent] {
        snapshot.events.filter { $0.end > now && !$0.isDeclined }.sorted { $0.start < $1.start }
    }

    var body: some View {
        let limit = size == .small ? 1 : size == .medium ? 2 : 8
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: loc("Up Next"), symbol: "calendar", tint: Palette.red)
            if upcoming.isEmpty {
                Text(loc("No events today")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(upcoming.prefix(limit)) { event in
                AgendaRow(event: event, detail: event.start.formatted(date: .omitted, time: .shortened))
            }
        }
    }
}

struct EndsInWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let state = EndsInState(events: snapshot.events, at: now)
        let limit = switch size {
        case .small: 2
        case .medium: 3
        default: 6
        }
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: loc("Ends In"), symbol: "timer.circle", tint: Palette.red)
            if state.current.isEmpty {
                Text(state.next.map { loc("Free until \($0.start.formatted(date: .omitted, time: .shortened))") }
                    ?? loc("Free all day"))
                    .font(.system(size: 15, weight: .semibold))
            }
            ForEach(state.current.prefix(limit)) { event in
                HStack {
                    AgendaRow(event: event, detail: "")
                    Text(timerInterval: now ... max(event.end, now), countsDown: true)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                }
            }
            if state.current.count > limit {
                Text("+\(state.current.count - limit)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

struct TodoWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let open = TodoFilter.all.apply(to: snapshot.todos, now: now)
        let limit = size == .small ? 3 : size == .medium ? 3 : 10
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("To-Do"), symbol: "checklist", tint: Palette.blue)
            Text("\(open.count)").font(.system(size: 30, weight: .semibold, design: .rounded))
            ForEach(open.prefix(limit)) { item in
                HStack(spacing: 6) {
                    WidgetActionButton(action: .setTodo(id: item.id, completed: true)) {
                        Image(systemName: "circle").foregroundStyle(Color(hex: item.listColor))
                    }
                    Text(item.title).lineLimit(1)
                }
                .font(.system(size: 13))
            }
        }
    }
}

struct NoteWidget: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Note"), symbol: "note.text", tint: Palette.yellow)
            Text(snapshot.everyday.note.isEmpty ? loc("No note yet") : snapshot.everyday.note)
                .font(.system(size: 13))
                .foregroundStyle(snapshot.everyday.note.isEmpty ? .secondary : .primary)
        }
    }
}

struct TimerWidget: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let timer = snapshot.everyday.timers.min { $0.remaining(at: now) < $1.remaining(at: now) }
        VStack(spacing: 6) {
            RingGauge(
                value: timer.map { $0.remaining(at: now) / max($0.duration, 1) } ?? 0,
                tint: Palette.orange,
                lineWidth: 10
            ) {
                if let end = timer?.endDate {
                    Text(timerInterval: now ... max(end, now), countsDown: true)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                } else {
                    Text(timer?.remaining(at: now).clockText ?? "0:00")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                }
            }
            if let timer {
                WidgetActionButton(action: .toggleTimer(timer.id)) {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                        .frame(width: 44, height: 22)
                        .background(.quaternary, in: .capsule)
                }
            } else {
                presets
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension TimerWidget {
    /// Starting from the widget uses the same lengths as the Timers panel.
    var presets: some View {
        HStack(spacing: 4) {
            ForEach([5, 10, 25], id: \.self) { minutes in
                WidgetActionButton(action: .startTimer(seconds: Double(minutes) * 60)) {
                    Text(verbatim: "\(minutes)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                        .frame(width: 34, height: 20)
                        .background(.quaternary, in: .capsule)
                }
            }
        }
    }
}

struct CountdownWidget: View {
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        let next = snapshot.everyday.sortedDates(from: now).first
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: next?.title ?? loc("Countdown"), symbol: "hourglass", tint: Palette.red)
            Spacer()
            Text(next.map { "\($0.daysLeft(from: now))" } ?? "—")
                .font(.system(size: 46, weight: .semibold, design: .rounded))
            Text(loc("days to go")).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}

struct YearInDotsWidget: View {
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let days = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 3), count: 20), spacing: 3) {
            ForEach(1 ... days, id: \.self) { day in
                Circle()
                    .fill(day < today ? Color.primary.opacity(0.75) : day == today ? Palette.orange : Color.primary
                        .opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

struct MoonWidget: View {
    let now: Date

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: Astronomy.moonPhase(at: now).symbol).font(.system(size: 54))
            Text(Format.percent(Astronomy.moonIllumination(at: now))).font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DaylightWidget: View {
    let now: Date

    var body: some View {
        let times = Astronomy.sunTimes(on: now, latitude: 55.75, longitude: 37.62)
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Daylight"), symbol: "sunrise", tint: Palette.orange)
            Spacer()
            Text(times.daylight.map(CompactDuration.format) ?? "—")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            InfoRow(title: loc("Sunrise"), value: times.sunrise?.formatted(date: .omitted, time: .shortened) ?? "—")
            InfoRow(title: loc("Sunset"), value: times.sunset?.formatted(date: .omitted, time: .shortened) ?? "—")
        }
    }
}

struct StorageWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        let main = snapshot.volumes.first
        HStack(spacing: 16) {
            RingGauge(value: main?.freeShare ?? 0, tint: Palette.cyan, lineWidth: 10) {
                Text(main.map { Format.bytes(Double($0.free)) } ?? "—")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
            }
            .frame(width: 112, height: 112)
            if size != .small {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.volumes.dropFirst().prefix(4)) { volume in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(volume.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                ThinBar(value: 1 - volume.freeShare, tint: Palette.cyan)
                            }
                            if volume.isEjectable {
                                WidgetActionButton(action: .eject(path: volume.path)) {
                                    Image(systemName: "eject.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 22, height: 22)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TemperatureWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        let sample = snapshot.sensors
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: loc("Temperature"), symbol: "thermometer.medium", tint: Palette.red)
            Text(sample?.averageCPU.map(Format.temperature) ?? "—")
                .font(.system(size: 44, weight: .semibold, design: .rounded))
            Text(loc("avg CPU")).font(.system(size: 12)).foregroundStyle(.secondary)
            if size == .large || size == .extraLarge, let sample {
                Divider()
                ForEach(SensorGroup.allCases, id: \.self) { group in
                    if let value = sample.average(of: [group]) {
                        InfoRow(title: group.title, value: Format.temperature(value))
                    }
                }
            }
        }
    }
}

struct TopAppsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: loc("Top Apps"), symbol: "cpu", tint: Palette.blue)
            TopProcessRows(processes: snapshot.processes, limit: size == .medium || size == .small ? 4 : 10)
        }
    }
}

struct NetworkWidget: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Network"), symbol: "arrow.up.arrow.down", tint: Palette.teal)
            Spacer()
            Text("↓ \(Format.rate(snapshot.network?.download ?? 0, style: .precise))")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("↑ \(Format.rate(snapshot.network?.upload ?? 0, style: .precise))")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
