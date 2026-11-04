import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI

/// Renders a widget the way macOS sizes it, for snapshots.
@MainActor
func widgetSnapshot(
    _ view: some View,
    size: WidgetSize,
    dark: Bool,
    named name: String,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line
) {
    let content = view
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(dark ? Color(red: 0.13, green: 0.12, blue: 0.19) : Color(red: 0.96, green: 0.95, blue: 0.98))
        .environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: content)
    host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
    withSnapshotTesting(record: record ? .all : .missing) {
        assertSnapshot(
            of: host,
            as: .image(precision: 0.98),
            named: name,
            file: file,
            testName: testName,
            line: line
        )
    }
}

/// A wave of values ending at `now`, so charts have a shape that stays the same between runs.
func samplePoints(
    count: Int,
    step: TimeInterval,
    base: Double,
    swing: Double,
    phase: Double = 0
) -> [History<Double>.Point] {
    (0 ..< count).map { index in
        let wave = sin(Double(index) * 0.7 + phase) + 0.5 * sin(Double(index) * 0.23 + phase)
        return History<Double>.Point(
            date: sampleNow.addingTimeInterval(Double(index - count) * step),
            value: base + wave * swing
        )
    }
}

enum DataSamples {
    static let fans = [
        FanReading(id: 0, rpm: 2400, minimum: 1200, maximum: 6000, target: 0),
        FanReading(id: 1, rpm: 2350, minimum: 1200, maximum: 6000, target: 0),
    ]

    static func sensors(fans: [FanReading] = fans) -> SensorSample {
        SensorSample(readings: [
            SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 47),
            SensorReading(key: "Tg01", group: .gpu, celsius: 42),
            SensorReading(key: "Ts01", group: .soc, celsius: 44),
            SensorReading(key: "TH0a", group: .storage, celsius: 38),
            SensorReading(key: "TB0T", group: .battery, celsius: 31),
            SensorReading(key: "TaLP", group: .ambient, celsius: 29),
        ], fans: fans)
    }

    static var fanSnapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.sensors = sensors()
        snapshot.fans = WidgetFanState(control: .ready, customRPM: 3600)
        snapshot.fanHistory = [
            0: samplePoints(count: 60, step: 10, base: 2400, swing: 60),
            1: samplePoints(count: 60, step: 10, base: 2350, swing: 60, phase: 1),
        ]
        return snapshot
    }

    static func fans(_ change: (inout WidgetSnapshot) -> Void) -> WidgetSnapshot {
        var snapshot = fanSnapshot
        change(&snapshot)
        return snapshot
    }

    static var weather: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        var other = sampleReport()
        other.place = WeatherPlace(id: 2, name: "Tbilisi", country: "Georgia", latitude: 41.7, longitude: 44.8)
        other.current.condition = .clear
        snapshot.weather = WidgetWeather(reports: [sampleReport(), other])
        return snapshot
    }

    static var rates: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        let saved = sampleRates()
        snapshot.rates = WidgetRates(quotes: saved.quotes, updatedAt: saved.updatedAt)
        return snapshot
    }

    private static func repository(
        _ name: String,
        branch: String,
        changed: Int = 0,
        ahead: Int = 0,
        behind: Int = 0
    ) -> GitRepository {
        var status = GitStatus()
        status.branch = branch
        status.upstream = "origin/\(branch)"
        status.changed = changed
        status.ahead = ahead
        status.behind = behind
        return GitRepository(
            path: "/Users/me/Developer/\(name)",
            status: status,
            lastCommit: sampleNow.addingTimeInterval(-7200)
        )
    }

    static var git: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.git = .repositories([
            repository("glasswork", branch: "feature/glass-cards", changed: 3, ahead: 2),
            repository("pocket-api", branch: "main", behind: 1),
            repository("dotfiles", branch: "main"),
            repository("notes-site", branch: "fix/rss-dates", changed: 1),
            repository("swift-snippets", branch: "main"),
            repository("pocket-ios", branch: "release/1.4", ahead: 1),
        ])
        return snapshot
    }

    static var devServers: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.devServers = .servers([
            DevServer(
                port: 3000, pid: 48213, process: "node", tool: "next dev", project: "glasswork", kind: .web,
                uptime: 8040
            ),
            DevServer(port: 5173, pid: 48301, process: "node", tool: "vite", project: "docs", kind: .web, uptime: 2880),
            DevServer(
                port: 8080, pid: 48410, process: "python3", tool: "uvicorn", project: "pocket-api", kind: .web,
                uptime: 18120
            ),
            DevServer(port: 5432, pid: 412, process: "postgres", project: "postgres", kind: .service, uptime: 259_200),
        ])
        return snapshot
    }

    static var containers: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.docker = .containers([
            DockerContainer(
                id: "1", name: "postgres-16", image: "postgres:16", status: "Up 3 hours", isRunning: true,
                ports: ["5432→5432"]
            ),
            DockerContainer(
                id: "2", name: "redis", image: "redis:7-alpine", status: "Up 3 hours", isRunning: true,
                ports: ["6379→6379"]
            ),
            DockerContainer(
                id: "3", name: "pocket-api-worker", image: "pocket-api-worker:dev", status: "Up 12 minutes",
                isRunning: true, ports: []
            ),
            DockerContainer(
                id: "4", name: "mailpit", image: "axllent/mailpit", status: "Up 3 hours", isRunning: true,
                ports: ["8025→8025"]
            ),
            DockerContainer(
                id: "5", name: "minio", image: "minio/minio", status: "Exited (0) 2 days ago", isRunning: false,
                ports: ["9000→9000", "9001→9001"]
            ),
        ], context: "orbstack")
        return snapshot
    }

    static var devices: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.devices = [
            DeviceBattery(name: "Magic Mouse", kind: .mouse, charge: 0.45),
            DeviceBattery(name: "AirPods Case", kind: .headphones, charge: 0.64),
            DeviceBattery(name: "Magic Keyboard", kind: .keyboard, charge: 0.71),
            DeviceBattery(name: "AirPods Pro", kind: .headphones, charge: 0.8),
            DeviceBattery(name: "Magic Trackpad", kind: .trackpad, charge: 0.93),
        ]
        return snapshot
    }

    static var wifi: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.wifi = .connected(WiFiLink(
            rssi: -54, noise: -92, transmitRate: 866, channel: 149, bandCode: 2, widthCode: 3, phyCode: 6
        ))
        snapshot.wifiHistory = samplePoints(count: 120, step: 5, base: 46, swing: 3)
        return snapshot
    }

    static var disk: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.diskActivity = DiskActivity(read: 120_000_000, write: 34_000_000)
        let read = samplePoints(count: 30, step: 2, base: 90_000_000, swing: 50_000_000)
        let write = samplePoints(count: 30, step: 2, base: 30_000_000, swing: 15_000_000, phase: 2)
        snapshot.diskMinute = WidgetDiskHistory(read: read, write: write)
        snapshot.diskLonger = WidgetDiskHistory(
            read: samplePoints(count: 30, step: 10, base: 80_000_000, swing: 50_000_000, phase: 1),
            write: samplePoints(count: 30, step: 10, base: 28_000_000, swing: 14_000_000, phase: 3)
        )
        snapshot.volumes = [
            DiskVolume(
                name: "Macintosh HD", path: "/", total: 494_000_000_000, free: 182_000_000_000, isInternal: true,
                isEjectable: false
            ),
            DiskVolume(
                name: "Backup", path: "/Volumes/Backup", total: 2_000_000_000_000, free: 1_210_000_000_000,
                isInternal: false, isEjectable: true
            ),
        ]
        return snapshot
    }

    static func timeMachine(_ status: TimeMachineStatus?) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.timeMachine = status
        return snapshot
    }

    static var backedUp: TimeMachineStatus {
        let backups = stride(from: 29.0, through: 0, by: -1)
            .filter { $0 != 11 && $0 != 20 }
            .map { sampleNow.addingTimeInterval(-$0 * 86400 - 3600) }
        return TimeMachineStatus(
            state: .idle,
            destination: "Backup",
            isAutomatic: true,
            lastBackup: backups.last,
            backups: backups
        )
    }

    /// A week of app use with today's sessions and breaks.
    static var screenTime: WidgetSnapshot {
        var log = ScreenTimeLog()
        log.categories = [
            "Xcode": .development, "Terminal": .development, "Notes": .productivity, "Mail": .productivity,
            "Slack": .communication, "Safari": .other, "Music": .entertainment,
        ]
        let days: [(back: Double, apps: [(String, Double)])] = [
            (9, [("Xcode", 9000), ("Safari", 4000)]),
            (8, [("Xcode", 8000), ("Slack", 3000)]),
            (6, [("Xcode", 7200), ("Safari", 3600), ("Slack", 2400)]),
            (5, [("Xcode", 6400), ("Safari", 3000), ("Slack", 1800), ("Music", 900)]),
            (4, [("Xcode", 9000), ("Safari", 4800), ("Slack", 3000)]),
            (3, [("Xcode", 7800), ("Notes", 2400), ("Slack", 2000)]),
            (2, [("Safari", 3000), ("Music", 2600)]),
            (1, [("Safari", 2400), ("Music", 1800)]),
        ]
        for day in days {
            for (app, seconds) in day.apps {
                log.record(app: app, seconds: seconds, at: sampleNow.addingTimeInterval(-day.back * 86400))
            }
        }
        recordToday(in: &log)
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.screenTime = log
        return snapshot
    }

    private static func recordToday(in log: inout ScreenTimeLog) {
        // Each stretch: an app with when it began and how long it ran, in minutes.
        let stretches: [(app: String, minutes: ClosedRange<Double>)] = [
            ("Xcode", 360 ... 420), ("Xcode", 322 ... 350), ("Safari", 290 ... 310), ("Terminal", 250 ... 280),
            ("Xcode", 195 ... 240), ("Slack", 155 ... 180), ("Xcode", 110 ... 150), ("Mail", 85 ... 100),
            ("Xcode", 48 ... 75),
        ]
        for item in stretches {
            let end = sampleNow.addingTimeInterval(-item.minutes.lowerBound * 60)
            log.record(app: item.app, seconds: (item.minutes.upperBound - item.minutes.lowerBound) * 60, at: end)
        }
        log.recordBreak(from: sampleNow.addingTimeInterval(-195 * 60), to: sampleNow.addingTimeInterval(-185 * 60))
        log.recordBreak(from: sampleNow.addingTimeInterval(-60 * 60), to: sampleNow.addingTimeInterval(-48 * 60))
    }
}
