import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The clocks, focus tools and daily facts with data, in both appearances. Views read only the date they are given,
/// so these stay stable between runs. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct TimeWidgetSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_793_750_000)

    nonisolated static let kinds: [WidgetKind] = [
        .clock,
        .numeralsClock,
        .minimalClock,
        .flipClock,
        .skyClock,
        .dayAndNight,
        .weekend,
        .progress,
        .stopwatch,
        .pomodoro,
        .focusTime,
        .wordOfDay,
    ]

    private var sample: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: Self.now)
        snapshot.everyday.cities = [
            WorldCity(name: "London", timeZone: "Europe/London"),
            WorldCity(name: "Tokyo", timeZone: "Asia/Tokyo"),
            WorldCity(name: "New York", timeZone: "America/New_York"),
            WorldCity(name: "Sydney", timeZone: "Australia/Sydney"),
            WorldCity(name: "Dubai", timeZone: "Asia/Dubai"),
            WorldCity(name: "Lima", timeZone: "America/Lima"),
        ]
        var stopwatch = Stopwatch()
        stopwatch.accumulated = 754
        snapshot.everyday.stopwatch = stopwatch
        var pomodoro = PomodoroSession()
        pomodoro.start(at: Self.now.addingTimeInterval(-40 * 60))
        pomodoro.history = [
            ScreenTimeLog.dayKey(Self.now.addingTimeInterval(-86400)): 6,
            ScreenTimeLog.dayKey(Self.now.addingTimeInterval(-2 * 86400)): 3,
        ]
        snapshot.everyday.pomodoro = pomodoro
        var log = ScreenTimeLog()
        for (back, apps) in [
            (2.0, [("Xcode", 5400.0)]),
            (1.0, [("Xcode", 9000.0), ("Safari", 3000.0)]),
            (0.0, [("Xcode", 7200.0), ("Safari", 1800.0), ("Mail", 600.0)]),
        ] {
            for (name, seconds) in apps {
                log.record(app: name, seconds: seconds, at: Self.now.addingTimeInterval(-back * 86400))
            }
        }
        snapshot.screenTime = log
        snapshot.words = [
            WordOfDay(day: "2026-11-04", word: "gleam", entry: DictionaryEntry(
                pronunciation: "ɡliːm",
                partOfSpeech: "noun",
                definition: "a faint or brief light, often one reflected from something"
            )),
            WordOfDay(day: "2026-11-03", word: "lantern", entry: DictionaryEntry(
                partOfSpeech: "noun",
                definition: "a lamp with a transparent case protecting the flame or electric bulb"
            )),
            WordOfDay(day: "2026-11-02", word: "glow", entry: DictionaryEntry(
                partOfSpeech: "noun",
                synonyms: ["radiance", "gleam", "shine"],
                example: "the glow of the embers."
            )),
            WordOfDay(
                day: "2026-11-01",
                word: "ember",
                entry: DictionaryEntry(definition: "a small piece of burning coal")
            ),
        ]
        snapshot.place = WeatherPlace(id: 1, name: "Moscow", country: "Russia", latitude: 55.75, longitude: 37.62)
        return snapshot
    }

    private func render(_ kind: WidgetKind, _ size: WidgetSize, dark: Bool) {
        let view = WidgetFace(kind: kind, size: size, snapshot: sample, now: Self.now)
            .padding(16)
            .frame(width: size.width, height: size.height)
            .background(dark ? Color(red: 0.13, green: 0.12, blue: 0.19) : Color(white: 0.96))
            .environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let name = "\(kind.rawValue)-\(size.rawValue)-\(dark ? "dark" : "light")"
        assertSnapshot(of: host, as: .image(precision: 0.98), named: name)
    }

    @Test(arguments: kinds)
    func darkEverySize(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            render(kind, size, dark: true)
        }
    }

    @Test func daylightChartHover() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600) ?? .gmt
        let days = Astronomy.daylight(
            from: Self.now,
            days: 14,
            latitude: 55.75,
            longitude: 37.62,
            calendar: calendar
        )
        let chart = InteractiveChart(
            series: [.daylight(days)],
            height: 100,
            tooltipDate: Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: calendar.timeZone),
            initialHover: days[6].date
        )
        .frame(width: 330)
        .padding(.bottom, 60)
        .padding(16)
        .background(Color(red: 0.13, green: 0.12, blue: 0.19))
        .environment(\.colorScheme, .dark)
        let host = NSHostingView(rootView: chart)
        host.frame = CGRect(x: 0, y: 0, width: 362, height: 200)
        host.appearance = NSAppearance(named: .darkAqua)
        assertSnapshot(of: host, as: .image(precision: 0.98), named: "daylight-chart-hover")
    }

    @Test(arguments: kinds)
    func lightEverySize(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            render(kind, size, dark: false)
        }
    }
}
