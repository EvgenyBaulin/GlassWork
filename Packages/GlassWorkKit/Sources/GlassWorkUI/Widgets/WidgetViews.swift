import GlassWorkCore
import SwiftUI

public extension WidgetKind {
    var title: String {
        switch self {
        case .activity: loc("Activity")
        case .battery: loc("Battery")
        case .macHealth: loc("Mac Health")
        case .uptime: loc("Uptime")
        case .screenTime: loc("Screen Time")
        case .commands: loc("Commands")
        case .endpoints: loc("Endpoints")
        case .githubReviews: loc("Reviews")
        case .githubActions: loc("GitHub Actions")
        case .contributions: loc("GitHub Contributions")
        case .storage: loc("Storage and Drives")
        case .temperature: loc("Temperature and Fans")
        case .topApps: loc("Top Apps")
        case .network: loc("Network")
        case .digitalClock: loc("Digital Clock")
        case .modularClock: loc("Modular Clock")
        case .calendarMonth: loc("Calendar Month")
        case .upNext: loc("Up Next")
        case .endsIn: loc("Ends In")
        case .todo: loc("To-Do")
        case .note: loc("Note")
        case .timer: loc("Timer")
        case .countdown: loc("Countdown")
        case .yearInDots: loc("Year in Dots")
        case .moon: loc("Moon")
        case .daylight: loc("Daylight")
        case .clock: loc("Clock")
        case .numeralsClock: loc("Numerals Clock")
        case .minimalClock: loc("Minimal Clock")
        case .flipClock: loc("Flip Clock")
        case .skyClock: loc("Sky Clock")
        case .dayAndNight: loc("Day and Night")
        case .weekend: loc("Weekend")
        case .progress: loc("Progress")
        case .stopwatch: loc("Stopwatch")
        case .pomodoro: loc("Pomodoro")
        case .focusTime: loc("Focus Time")
        case .wordOfDay: loc("Word of the Day")
        case .fans: loc("Fans")
        case .weather: loc("Weather")
        case .rates: loc("Rates")
        case .git: loc("Git")
        case .devServers: loc("Dev Servers")
        case .containers: loc("Containers")
        case .aiUsage: ModuleID.aiUsage.title
        case .devices: loc("Devices")
        case .wifiSignal: loc("Wi-Fi Signal")
        case .diskActivity: loc("Disk Activity")
        case .timeMachine: loc("Time Machine")
        case .screenTimeWeek: loc("Screen Time Week")
        case .categories: loc("Categories")
        case .breaks: loc("Breaks")
        case .appTime: loc("App Time")
        case .mostUsed: loc("Most Used")
        case .nowPlaying: loc("Now Playing")
        case .lyrics: loc("Lyrics")
        case .github: loc("GitHub")
        case .todayAtAGlance: loc("Today at a Glance")
        case .photoFrame: loc("Photo Frame")
        case .onThisDay: loc("On This Day")
        case .birthdays: loc("Birthdays")
        }
    }
}

public extension WidgetKind {
    /// The module whose panel a click on this widget opens.
    var module: ModuleID {
        switch self {
        case .activity, .macHealth: .overview
        case .battery: .battery
        case .storage: .disk
        case .temperature: .sensors
        case .topApps: .cpu
        case .network: .network
        case .uptime: .uptime
        case .screenTime, .commands, .endpoints, .githubReviews, .githubActions, .contributions: .overview
        case .digitalClock, .modularClock, .calendarMonth, .yearInDots: .date
        case .clock, .numeralsClock, .minimalClock, .flipClock: .worldClocks
        case .upNext: .calendar
        case .endsIn: .endsIn
        case .todo: .todos
        case .note: .notes
        case .timer: .timers
        case .countdown: .countdown
        case .moon, .daylight, .skyClock, .dayAndNight: .sunMoon
        case .weekend, .progress: .date
        case .stopwatch, .pomodoro: .timers
        case .focusTime: .overview
        case .wordOfDay: .date
        case .fans: .fans
        case .weather: .weather
        case .rates: .rates
        case .git: .git
        case .devServers: .devServers
        case .containers: .docker
        case .aiUsage: .aiUsage
        case .devices: .deviceBatteries
        case .wifiSignal: .wifi
        case .diskActivity: .disk
        case .timeMachine, .screenTimeWeek, .categories, .breaks, .appTime, .mostUsed: .overview
        case .nowPlaying, .lyrics: .nowPlaying
        case .github: .overview
        case .todayAtAGlance: .calendar
        case .photoFrame, .onThisDay, .birthdays: .overview
        }
    }
}

public extension WidgetKind {
    /// Where a click on a system widget leads: the place that explains the widget or changes what it shows.
    var destination: WidgetDestination {
        switch self {
        // No panel shows these. Settings is where they are turned on or filled in.
        case .photoFrame, .onThisDay, .birthdays, .commands, .endpoints,
             .screenTime, .screenTimeWeek, .categories, .breaks, .appTime, .mostUsed, .focusTime:
            .widgetSettings
        case .github, .githubReviews: WidgetLink.githubReviews.map(WidgetDestination.web) ?? .module(.overview)
        case .githubActions, .contributions: WidgetLink.githubHome.map(WidgetDestination.web) ?? .module(.overview)
        case .timeMachine: .module(.disk)
        default: .module(module)
        }
    }
}

/// One widget face, shared by WidgetKit and GlassWork's own desktop windows.
public struct WidgetFace: View {
    private let kind: WidgetKind
    private let size: WidgetSize
    private let snapshot: WidgetSnapshot
    private let now: Date
    private let showsSeconds: Bool

    /// `showsSeconds` is false in WidgetKit, which refreshes once a minute and would show stale seconds.
    public init(
        kind: WidgetKind,
        size: WidgetSize,
        snapshot: WidgetSnapshot,
        now: Date = .now,
        showsSeconds: Bool = true
    ) {
        self.kind = kind
        self.size = size
        self.snapshot = snapshot
        self.now = now
        self.showsSeconds = showsSeconds
    }

    public var body: some View {
        Group {
            switch kind {
            case .activity: ActivityWidget(size: size, snapshot: snapshot)
            case .battery: BatteryWidget(size: size, snapshot: snapshot)
            case .macHealth, .uptime: MacHealthWidget(size: size, snapshot: snapshot, now: now)
            case .digitalClock: DigitalClockWidget(size: size, now: now)
            case .commands: CommandsWidget(size: size, snapshot: snapshot)
            case .endpoints: EndpointsWidget(size: size, snapshot: snapshot)
            case .githubReviews: ReviewsWidget(size: size, snapshot: snapshot)
            case .githubActions: ActionsWidget(size: size, snapshot: snapshot)
            case .contributions: ContributionsWidget(size: size, snapshot: snapshot)
            case .modularClock: ModularClockWidget(size: size, now: now)
            case .calendarMonth: CalendarMonthWidget(now: now)
            case .upNext: UpNextWidget(size: size, snapshot: snapshot, now: now)
            case .endsIn: EndsInWidget(size: size, snapshot: snapshot, now: now)
            case .todo: TodoWidget(size: size, snapshot: snapshot, now: now)
            case .note: NoteWidget(snapshot: snapshot)
            case .timer: TimerWidget(snapshot: snapshot, now: now)
            case .countdown: CountdownWidget(snapshot: snapshot, now: now)
            case .yearInDots: YearInDotsWidget(now: now)
            case .moon: MoonWidget(now: now)
            case .daylight: DaylightWidget(now: now)
            case .storage: StorageWidget(size: size, snapshot: snapshot)
            case .temperature: TemperatureWidget(size: size, snapshot: snapshot)
            case .topApps: TopAppsWidget(size: size, snapshot: snapshot)
            case .network: NetworkWidget(snapshot: snapshot)
            case .nowPlaying:
                NowPlayingWidget(size: size, data: snapshot.nowPlaying, now: now, isSystemTimed: !showsSeconds)
            case .lyrics:
                LyricsWidget(size: size, data: snapshot.nowPlaying, now: now, isSystemTimed: !showsSeconds)
            default:
                DataWidgetFace(
                    kind: kind,
                    context: TimeContext(size: size, snapshot: snapshot, now: now, showsSeconds: showsSeconds)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ActivityWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    private struct Ring {
        let title: String
        let value: Double
        let tint: Color
    }

    private var rings: [Ring] {
        [
            Ring(title: loc("CPU"), value: snapshot.cpu?.total ?? 0, tint: Palette.blue),
            Ring(title: loc("Memory"), value: snapshot.memory?.usedShare ?? 0, tint: Palette.green),
            Ring(title: loc("GPU"), value: snapshot.gpu?.device ?? 0, tint: Palette.purple),
        ]
    }

    var body: some View {
        switch size {
        case .small:
            ring(rings[0], diameter: 112).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .medium:
            HStack(spacing: 14) { ForEach(rings, id: \.title) { ring($0, diameter: 92) } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .large, .extraLarge:
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) { ForEach(rings, id: \.title) { ring($0, diameter: 92) } }
                    .frame(maxWidth: .infinity)
                Divider()
                TopProcessRows(processes: snapshot.topUsage, limit: size == .large ? 5 : 8)
            }
        }
    }

    private func ring(_ item: Ring, diameter: CGFloat) -> some View {
        VStack(spacing: 6) {
            RingGauge(value: item.value, tint: item.tint, lineWidth: diameter / 9) {
                Text(Format.percent(item.value))
                    .font(.system(size: diameter / 5, weight: .semibold, design: .rounded))
            }
            .frame(width: diameter, height: diameter)
            Text(item.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct TopProcessRows: View {
    let processes: [ProcessUsage]
    let limit: Int

    var body: some View {
        let top = processes.sorted { $0.cpu > $1.cpu }.prefix(limit)
        let peak = max(top.first?.cpu ?? 1, 0.1)
        VStack(spacing: 6) {
            ForEach(Array(top)) { process in
                HStack(spacing: 8) {
                    Text(process.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    ThinBar(value: process.cpu / peak, tint: Palette.blue).frame(width: 90)
                    Text(String(format: "%.1f%%", process.cpu)).monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                .font(.system(size: 12))
            }
        }
    }
}

struct BatteryWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        if let battery = snapshot.battery {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                    .font(.system(size: 34))
                    .foregroundStyle(tint(battery))
                Spacer()
                Text(Format.percent(battery.charge))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(status(battery))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(battery.isCharging ? Palette.green : .secondary)
            }
        } else {
            Text(loc("This Mac has no battery")).foregroundStyle(.secondary)
        }
    }

    private func tint(_ battery: BatterySample) -> Color {
        battery.charge <= 0.2 && !battery.isCharging ? Palette.red : Palette.green
    }

    private func status(_ battery: BatterySample) -> String {
        battery.isCharging ? loc("Charging") : battery.isOnAC ? loc("Power Adapter") : loc("On battery")
    }
}

struct MacHealthWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacHealthTitle(text: loc("Running smoothly"))
            if let boot = snapshot.bootTime {
                Text(CompactDuration.format(now.timeIntervalSince(boot)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
            }
            Spacer()
            if let memory = snapshot.memory {
                InfoRow(title: loc("Memory"), value: Format.percent(memory.usedShare))
                InfoRow(title: loc("Swap used"), value: Format.bytes(Double(memory.swapUsed), style: .precise))
            }
        }
    }
}

/// The desktop gives a small widget less room than its nominal size, so the text shrinks instead of being cut.
struct MacHealthTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill")
            Text(text).lineLimit(1).minimumScaleFactor(0.6)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Palette.green)
    }
}

struct DigitalClockWidget: View {
    let size: WidgetSize
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.orange)
            Text(now, style: .time)
                .font(.system(size: size == .small ? 38 : 60, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
            Text(now.formatted(.dateTime.day().month(.wide)))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
