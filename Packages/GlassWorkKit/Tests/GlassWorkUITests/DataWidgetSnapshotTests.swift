import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing
import WidgetKit

/// Live-data widgets with data, every size in both appearances. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DataWidgetSnapshotTests {
    nonisolated static let kinds: [WidgetKind] = [
        .fans, .weather, .rates, .git, .devServers, .containers, .devices, .wifiSignal, .diskActivity, .timeMachine,
        .screenTime, .screenTimeWeek, .categories, .breaks, .appTime, .mostUsed,
    ]

    private func sample(_ kind: WidgetKind) -> WidgetSnapshot {
        switch kind {
        case .fans: DataSamples.fanSnapshot
        case .weather: DataSamples.weather
        case .rates: DataSamples.rates
        case .git: DataSamples.git
        case .devServers: DataSamples.devServers
        case .containers: DataSamples.containers
        case .devices: DataSamples.devices
        case .wifiSignal: DataSamples.wifi
        case .diskActivity: DataSamples.disk
        case .timeMachine: DataSamples.timeMachine(DataSamples.backedUp)
        default: DataSamples.screenTime
        }
    }

    @Test(arguments: kinds)
    func rendersEverySizeInBothAppearances(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            for dark in [true, false] {
                widgetSnapshot(
                    WidgetFace(kind: kind, size: size, snapshot: sample(kind), now: sampleNow),
                    size: size,
                    dark: dark,
                    named: "\(kind.rawValue)-\(size.rawValue)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    private func state(_ kind: WidgetKind, _ snapshot: WidgetSnapshot, _ name: String, sizes: [WidgetSize]) {
        for size in sizes {
            widgetSnapshot(
                WidgetFace(kind: kind, size: size, snapshot: snapshot, now: sampleNow),
                size: size,
                dark: true,
                named: "\(kind.rawValue)-\(name)-\(size.rawValue)"
            )
        }
    }

    @Test func fansWithMaxOn() {
        let snapshot = DataSamples.fans { snapshot in
            snapshot.sensors = DataSamples.sensors(fans: [
                FanReading(id: 0, rpm: 5800, minimum: 1200, maximum: 6000),
                FanReading(id: 1, rpm: 5600, minimum: 1200, maximum: 6000),
            ])
            snapshot.fans?.mode = .max
        }
        state(.fans, snapshot, "max", sizes: WidgetSize.allCases)
    }

    /// The desktop gives a small widget less room than its nominal size, so this is tighter than any real one.
    @Test(arguments: ["Running smoothly", "Всё работает"])
    func uptimeTitleFitsATightWidget(title: String) {
        let view = MacHealthTitle(text: title).frame(width: 100, height: 20, alignment: .leading)
        let host = NSHostingView(rootView: view.padding(8).background(.black).environment(\.colorScheme, .dark))
        host.frame = CGRect(x: 0, y: 0, width: 116, height: 36)
        withSnapshotTesting(record: .missing) {
            assertSnapshot(of: host, as: .image(precision: 0.98), named: title == "Всё работает" ? "ru" : "en")
        }
    }

    @Test func activityListsAppsByTheirNames() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.cpu = CPUSample(total: 0.27, user: 0.18, system: 0.09, idle: 0.73, cores: [0.3, 0.2])
        snapshot.processes = [ProcessUsage(pid: 9, name: "com.apple.WebKit.WebContent", cpu: 40, memory: 1)]
        snapshot.apps = [
            ProcessUsage(pid: 1, name: "Google Chrome", cpu: 41.2, memory: 1),
            ProcessUsage(pid: 2, name: "Xcode", cpu: 19.3, memory: 1),
        ]
        state(.activity, snapshot, "apps", sizes: [.large])
    }

    @Test func fansWithoutTheService() {
        let snapshot = DataSamples.fans { $0.fans?.control = .notInstalled }
        state(.fans, snapshot, "no-service", sizes: WidgetSize.allCases)
    }

    @Test func fansWaitingForApproval() {
        let snapshot = DataSamples.fans { $0.fans?.control = .needsApproval }
        state(.fans, snapshot, "needs-approval", sizes: [.medium])
    }

    @Test func fansAfterTheFailsafe() {
        let snapshot = DataSamples.fans { snapshot in
            snapshot.fans?.mode = .max
            snapshot.fans?.notice = .failsafeMax(celsius: 96)
        }
        state(.fans, snapshot, "failsafe", sizes: [.medium, .large])
    }

    @Test func fansBackOnAuto() {
        let snapshot = DataSamples.fans { $0.fans?.notice = .returnedToAuto }
        state(.fans, snapshot, "back-to-auto", sizes: [.medium])
    }

    @Test func fansOnACurve() {
        let snapshot = DataSamples.fans { $0.fans?.mode = .curve }
        state(.fans, snapshot, "curve", sizes: WidgetSize.allCases)
    }

    @Test func fansOnAFanlessMac() {
        let snapshot = DataSamples.fans { $0.sensors = DataSamples.sensors(fans: []) }
        state(.fans, snapshot, "none", sizes: [.small, .medium])
    }

    @Test func fansChartOnHover() {
        let context = TimeContext(size: .large, snapshot: DataSamples.fanSnapshot, now: sampleNow, showsSeconds: true)
        widgetSnapshot(
            FansWidget(context: context, chartHover: sampleNow.addingTimeInterval(-300)),
            size: .large,
            dark: true,
            named: "fans-hover"
        )
    }

    @Test func offlineWeatherAndRates() {
        var weather = DataSamples.weather
        weather.weather?.isStale = true
        state(.weather, weather, "offline", sizes: [.small, .medium])
        var rates = DataSamples.rates
        rates.rates?.isStale = true
        state(.rates, rates, "offline", sizes: [.small, .medium])
    }

    @Test func ratesChartOnHover() {
        let snapshot = DataSamples.rates
        let hover = snapshot.rates?.quotes.first?.history[3].date
        let context = TimeContext(size: .medium, snapshot: snapshot, now: sampleNow, showsSeconds: true)
        widgetSnapshot(
            RatesWidget(context: context, chartHover: hover),
            size: .medium,
            dark: true,
            named: "rates-hover"
        )
    }

    @Test func gitStates() {
        var clean = WidgetSnapshot(date: sampleNow)
        var status = GitStatus()
        status.branch = "main"
        clean.git = .repositories([GitRepository(path: "/tmp/site", status: status)])
        state(.git, clean, "up-to-date", sizes: [.small])
        var missing = WidgetSnapshot(date: sampleNow)
        missing.git = .notInstalled
        state(.git, missing, "no-tool", sizes: [.medium])
    }

    /// A new widget has no data for up to a minute, and must not claim that nothing exists.
    @Test(arguments: [
        WidgetKind.fans, .weather, .git, .devServers, .containers, .devices, .wifiSignal,
    ])
    func waitsForItsFirstData(kind: WidgetKind) {
        state(kind, WidgetSnapshot(date: sampleNow), "waiting", sizes: [.small])
    }

    @Test func gitWithNoRepositories() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.git = .repositories([])
        state(.git, snapshot, "none", sizes: [.small, .medium])
    }

    @Test func weatherWithNoPlace() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.weather = WidgetWeather(hasPlaces: false)
        state(.weather, snapshot, "no-place", sizes: [.small, .medium])
    }

    @Test func devicesWithNoAccessories() {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.devices = []
        state(.devices, snapshot, "none", sizes: [.small, .medium])
    }

    @Test func containersStates() {
        var stopped = WidgetSnapshot(date: sampleNow)
        stopped.docker = .notRunning
        state(.containers, stopped, "not-running", sizes: [.small, .medium])
        var empty = WidgetSnapshot(date: sampleNow)
        empty.docker = .containers([], context: nil)
        state(.containers, empty, "empty", sizes: [.small])
    }

    @Test func wifiStates() {
        var off = WidgetSnapshot(date: sampleNow)
        off.wifi = .off
        state(.wifiSignal, off, "off", sizes: [.small, .medium])
    }

    @Test func wifiChartOnHover() {
        let context = TimeContext(size: .large, snapshot: DataSamples.wifi, now: sampleNow, showsSeconds: true)
        widgetSnapshot(
            WiFiSignalWidget(context: context, chartHover: sampleNow.addingTimeInterval(-120)),
            size: .large,
            dark: true,
            named: "wifi-hover"
        )
    }

    @Test func diskChartOnHover() {
        let snapshot = DataSamples.disk
        let hover = snapshot.diskLonger?.read[12].date
        let context = TimeContext(size: .large, snapshot: snapshot, now: sampleNow, showsSeconds: true)
        widgetSnapshot(
            DiskActivityWidget(context: context, chartHover: hover),
            size: .large,
            dark: true,
            named: "disk-hover"
        )
    }

    @Test func timeMachineStates() {
        let sizes = WidgetSize.allCases
        state(.timeMachine, DataSamples.timeMachine(TimeMachineStatus(state: .notConfigured)), "no-disk", sizes: sizes)
        state(
            .timeMachine,
            DataSamples.timeMachine(TimeMachineStatus(state: .idle, destination: "Backup")),
            "never",
            sizes: [.medium]
        )
        state(
            .timeMachine,
            DataSamples.timeMachine(TimeMachineStatus(
                state: .idle,
                destination: "Backup",
                lastBackup: sampleNow.addingTimeInterval(-40 * 86400)
            )),
            "overdue",
            sizes: [.small, .medium]
        )
        state(
            .timeMachine,
            DataSamples.timeMachine(TimeMachineStatus(
                state: .running(progress: 0.42, secondsLeft: 540),
                destination: "Backup"
            )),
            "running",
            sizes: sizes
        )
        state(
            .timeMachine,
            DataSamples.timeMachine(TimeMachineStatus(state: .needsPermission, destination: "Backup")),
            "permission",
            sizes: sizes
        )
    }

    @Test func screenTimeChartsOnHover() {
        let snapshot = DataSamples.screenTime
        let context = TimeContext(size: .extraLarge, snapshot: snapshot, now: sampleNow, showsSeconds: true)
        let day = Calendar.current.startOfDay(for: sampleNow).addingTimeInterval(-2 * 86400)
        widgetSnapshot(
            ScreenTimeWidget(context: context, chartHover: day),
            size: .extraLarge,
            dark: true,
            named: "screen-time-hover"
        )
        widgetSnapshot(
            ScreenTimeWeekWidget(context: context, chartHover: day),
            size: .extraLarge,
            dark: true,
            named: "week-hover"
        )
        widgetSnapshot(
            CategoriesWidget(context: context, chartHover: day),
            size: .extraLarge,
            dark: true,
            named: "categories-hover"
        )
    }

    @Test func categoryRingOnHover() {
        let context = TimeContext(size: .medium, snapshot: DataSamples.screenTime, now: sampleNow, showsSeconds: true)
        widgetSnapshot(
            CategoriesWidget(context: context, donutHover: .communication),
            size: .medium,
            dark: true,
            named: "ring-hover"
        )
    }

    @Test func hourChartOnHover() {
        let sessions = DataSamples.screenTime.screenTime.today(sampleNow)?.sessions ?? []
        let hover = ScreenHours.today(sessions)[2].hour
        widgetSnapshot(
            ScreenHourChart(sessions: sessions, tint: Palette.purple, height: 120, hover: hover),
            size: .medium,
            dark: true,
            named: "hours-hover"
        )
    }

    /// White text on a filled button would vanish here, so Max falls back to the soft fill.
    @Test func fansWithMaxOnWhenRecolored() {
        let snapshot = DataSamples.fans { $0.fans?.mode = .max }
        widgetSnapshot(
            WidgetFace(kind: .fans, size: .medium, snapshot: snapshot, now: sampleNow)
                .environment(\.widgetRenderingMode, .accented),
            size: .medium,
            dark: true,
            named: "fans-max-accented"
        )
    }

    /// Accented is how macOS draws tinted and clear widgets; vibrant is the desaturated one.
    @Test(arguments: [WidgetKind.fans, .git, .containers, .devices, .breaks, .mostUsed])
    func rendersInTheSystemModes(kind: WidgetKind) {
        for (name, mode) in [("accented", WidgetRenderingMode.accented), ("vibrant", .vibrant)] {
            widgetSnapshot(
                WidgetFace(kind: kind, size: .medium, snapshot: sample(kind), now: sampleNow)
                    .environment(\.widgetRenderingMode, mode),
                size: .medium,
                dark: true,
                named: "\(kind.rawValue)-\(name)"
            )
        }
    }
}
