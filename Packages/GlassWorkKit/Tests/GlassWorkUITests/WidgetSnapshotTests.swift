import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Every widget in every size, dark. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct WidgetSnapshotTests {
    private static let now = Date(timeIntervalSince1970: 1_793_750_000)

    private var sample: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: Self.now)
        snapshot.cpu = CPUSample(total: 0.27, user: 0.18, system: 0.09, idle: 0.73, cores: [0.3, 0.2])
        snapshot.memory = VMCounters(
            pageSize: 16384, free: 100_000, wired: 200_000, compressor: 100_000,
            purgeable: 1000, external: 200_000, internal: 900_000
        ).sample(total: 36_000_000_000, swapUsed: 1_200_000_000, swapTotal: 2_000_000_000, pressure: .normal)
        snapshot.gpu = GPUSample(name: "Apple M3 Pro", device: 0.17, renderer: 0.15, tiler: 0.12, memoryInUse: 0)
        snapshot.battery = BatterySample(
            charge: 0.82, isCharging: true, isOnAC: true, minutesRemaining: 65,
            health: 0.91, cycleCount: 312, temperature: 31, adapterWatts: 96
        )
        snapshot.volumes = [
            DiskVolume(
                name: "Macintosh HD",
                path: "/",
                total: 494_000_000_000,
                free: 182_000_000_000,
                isInternal: true,
                isEjectable: false
            ),
            DiskVolume(
                name: "Backup",
                path: "/Volumes/Backup",
                total: 2_000_000_000_000,
                free: 1_210_000_000_000,
                isInternal: false,
                isEjectable: true
            ),
        ]
        snapshot.network = NetworkSample(
            download: 2_400_000,
            upload: 300_000,
            interfaces: [],
            sessionReceived: 0,
            sessionSent: 0
        )
        snapshot.sensors = SensorSample(readings: [
            SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 47),
            SensorReading(key: "Tg01", group: .gpu, celsius: 44),
            SensorReading(key: "TB0T", group: .battery, celsius: 31),
        ], fans: [])
        snapshot.processes = [
            ProcessUsage(pid: 1, name: "Xcode", cpu: 19.3, memory: 3_100_000_000),
            ProcessUsage(pid: 2, name: "Safari", cpu: 9, memory: 1_800_000_000),
        ]
        snapshot.everyday.note = "Ship the widgets"
        snapshot.everyday.dates = [ImportantDate(title: "Launch day", date: Self.now.addingTimeInterval(86400 * 12))]
        snapshot.events = [
            AgendaEvent(
                id: "1",
                title: "Standup",
                start: Self.now.addingTimeInterval(-600),
                end: Self.now.addingTimeInterval(900)
            ),
            AgendaEvent(
                id: "2",
                title: "Yoga",
                start: Self.now.addingTimeInterval(7000),
                end: Self.now.addingTimeInterval(9000)
            ),
        ]
        snapshot.todos = [TodoItem(id: "1", title: "Ship 1.0.4", listName: "Work")]
        snapshot.bootTime = Self.now.addingTimeInterval(-273_600)
        return snapshot
    }

    @Test(arguments: WidgetKind.allCases)
    func rendersEverySize(kind: WidgetKind) {
        for size in WidgetSize.allCases {
            let view = WidgetFace(kind: kind, size: size, snapshot: sample, now: Self.now)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(Color(red: 0.13, green: 0.12, blue: 0.19))
                .environment(\.colorScheme, .dark)
            let host = NSHostingView(rootView: view)
            host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            host.appearance = NSAppearance(named: .darkAqua)
            let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
            withSnapshotTesting(record: record ? .all : .missing) {
                assertSnapshot(of: host, as: .image(precision: 0.98), named: "\(kind.rawValue)-\(size.rawValue)")
            }
        }
    }
}
