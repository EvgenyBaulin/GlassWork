import GlassWorkCore
import GlassWorkUI
import SwiftUI
import WidgetKit

@main
struct GlassWorkWidgets: WidgetBundle {
    var body: some Widget {
        ActivityKindWidget()
        BatteryKindWidget()
        MacHealthKindWidget()
        UptimeKindWidget()
        DigitalClockKindWidget()
        NowPlayingKindWidget()
        LyricsKindWidget()
        MoreWidgets().body
        DataWidgets().body
        MacWidgets().body
    }
}

/// A widget bundle body takes at most ten widgets, so the rest are grouped here.
struct MoreWidgets: WidgetBundle {
    var body: some Widget {
        StorageKindWidget()
        TemperatureKindWidget()
        TopAppsKindWidget()
        NetworkKindWidget()
        ModularClockKindWidget()
        CalendarMonthKindWidget()
        UpNextKindWidget()
        EndsInKindWidget()
        EvenMoreWidgets().body
    }
}

struct EvenMoreWidgets: WidgetBundle {
    var body: some Widget {
        ScreenTimeKindWidget()
        CommandsKindWidget()
        EndpointsKindWidget()
        GithubReviewsKindWidget()
        GithubActionsKindWidget()
        ContributionsKindWidget()
        TodoKindWidget()
        NoteKindWidget()
        TimerKindWidget()
        CountdownKindWidget()
        YearInDotsKindWidget()
        MoonKindWidget()
        DaylightKindWidget()
        TimeWidgets().body
    }
}

/// Clocks, focus tools and daily facts.
struct TimeWidgets: WidgetBundle {
    var body: some Widget {
        ClockKindWidget()
        NumeralsClockKindWidget()
        MinimalClockKindWidget()
        FlipClockKindWidget()
        SkyClockKindWidget()
        DayAndNightKindWidget()
        WeekendKindWidget()
        ProgressKindWidget()
        StopwatchKindWidget()
        PomodoroKindWidget()
        FocusTimeKindWidget()
        WordOfDayKindWidget()
    }
}

/// Live readings and developer tools.
struct DataWidgets: WidgetBundle {
    var body: some Widget {
        FansKindWidget()
        WeatherKindWidget()
        RatesKindWidget()
        GitKindWidget()
        DevServersKindWidget()
        ContainersKindWidget()
        AIUsageKindWidget()
        GitHubKindWidget()
        TodayKindWidget()
        PhotoFrameKindWidget()
        OnThisDayKindWidget()
        BirthdaysKindWidget()
    }
}

/// The Mac's accessories and backups, and the rest of Screen Time.
struct MacWidgets: WidgetBundle {
    var body: some Widget {
        DevicesKindWidget()
        WifiSignalKindWidget()
        DiskActivityKindWidget()
        TimeMachineKindWidget()
        ScreenTimeWeekKindWidget()
        CategoriesKindWidget()
        BreaksKindWidget()
        AppTimeKindWidget()
        MostUsedKindWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    private let store = SnapshotStore()

    func placeholder(in _: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(date: .now))
    }

    func getSnapshot(in _: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// One entry a minute, so clocks and ages stay right between the app's refreshes.
    func getTimeline(in _: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let start = Date.now
        let snapshot = store.read(WidgetSnapshot.self, for: WidgetSnapshot.key)
        let entries = (0 ..< 15).map {
            SnapshotEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> SnapshotEntry {
        SnapshotEntry(date: date, snapshot: store.read(WidgetSnapshot.self, for: WidgetSnapshot.key))
    }
}

struct KindView: View {
    let kind: WidgetKind
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var size: WidgetSize {
        switch family {
        case .systemSmall: .small
        case .systemMedium: .medium
        case .systemLarge: .large
        default: .extraLarge
        }
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                WidgetFace(kind: kind, size: size, snapshot: snapshot, now: entry.date, showsSeconds: false)
            } else {
                Text(loc("Open GlassWork to start")).foregroundStyle(.secondary)
            }
        }
        .environment(\.widgetActions, .intents)
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(WidgetLink.url(for: kind.destination))
    }
}

@MainActor
private func configuration(_ kind: WidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: SnapshotProvider()) { entry in
        KindView(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.title)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
}

struct ActivityKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.activity)
    }
}

struct BatteryKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.battery)
    }
}

struct MacHealthKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.macHealth)
    }
}

struct UptimeKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.uptime)
    }
}

struct DigitalClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.digitalClock)
    }
}

struct StorageKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.storage)
    }
}

struct TemperatureKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.temperature)
    }
}

struct TopAppsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.topApps)
    }
}

struct NetworkKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.network)
    }
}

struct ModularClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.modularClock)
    }
}

struct CalendarMonthKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.calendarMonth)
    }
}

struct UpNextKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.upNext)
    }
}

struct EndsInKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.endsIn)
    }
}

struct TodoKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.todo)
    }
}

struct NoteKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.note)
    }
}

struct TimerKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.timer)
    }
}

struct CountdownKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.countdown)
    }
}

struct YearInDotsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.yearInDots)
    }
}

struct MoonKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.moon)
    }
}

struct DaylightKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.daylight)
    }
}

struct ScreenTimeKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.screenTime)
    }
}

struct CommandsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.commands)
    }
}

struct EndpointsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.endpoints)
    }
}

struct GithubReviewsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.githubReviews)
    }
}

struct GithubActionsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.githubActions)
    }
}

struct ContributionsKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.contributions)
    }
}

struct ClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.clock)
    }
}

struct NumeralsClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.numeralsClock)
    }
}

struct MinimalClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.minimalClock)
    }
}

struct FlipClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.flipClock)
    }
}

struct SkyClockKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.skyClock)
    }
}

struct DayAndNightKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.dayAndNight)
    }
}

struct WeekendKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.weekend)
    }
}

struct ProgressKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.progress)
    }
}

struct StopwatchKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.stopwatch)
    }
}

struct PomodoroKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.pomodoro)
    }
}

struct FocusTimeKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.focusTime)
    }
}

struct WordOfDayKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.wordOfDay)
    }
}

struct FansKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.fans)
    }
}

struct WeatherKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.weather)
    }
}

struct RatesKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.rates)
    }
}

struct GitKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.git)
    }
}

struct DevServersKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.devServers)
    }
}

struct ContainersKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.containers)
    }
}

struct AIUsageKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.aiUsage)
    }
}

struct DevicesKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.devices)
    }
}

struct WifiSignalKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.wifiSignal)
    }
}

struct DiskActivityKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.diskActivity)
    }
}

struct TimeMachineKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.timeMachine)
    }
}

struct ScreenTimeWeekKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.screenTimeWeek)
    }
}

struct CategoriesKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.categories)
    }
}

struct BreaksKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.breaks)
    }
}

struct AppTimeKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.appTime)
    }
}

struct BirthdaysKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.birthdays)
    }
}

struct GitHubKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.github)
    }
}

struct TodayKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.todayAtAGlance)
    }
}

struct MostUsedKindWidget: Widget {
    var body: some WidgetConfiguration {
        configuration(.mostUsed)
    }
}
