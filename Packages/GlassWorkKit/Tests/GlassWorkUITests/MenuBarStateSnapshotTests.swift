import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct MenuBarStateSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ content: ItemContent, module: ModuleID, name: String, dark: Bool) throws {
        let renderer = MenuBarItemRenderer(module: module, style: .figure, numbers: .compact, monitor: SystemMonitor())
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let textWidth = ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
        let size = CGSize(width: textWidth + 28, height: 24)
        let view = NSImageView(frame: CGRect(origin: .zero, size: size))
        view.image = try #require(renderer.image(content: content, size: size))
        view.contentTintColor = .labelColor
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }

    private func timer(_ seconds: Double, paused: Bool = false) -> CountdownTimer {
        var timer = CountdownTimer(title: "T", duration: seconds, start: now)
        if paused {
            timer.togglePause(at: now)
        }
        return timer
    }

    @Test(arguments: [true, false])
    func timers(dark: Bool) throws {
        try snapshot(
            ItemContent.timers([timer(900), timer(252)], at: now, options: [:]),
            module: .timers, name: "timers-several", dark: dark
        )
        try snapshot(
            ItemContent.timers([timer(252, paused: true)], at: now, options: [:]),
            module: .timers, name: "timers-paused", dark: dark
        )
    }

    @Test(arguments: [true, false])
    func worldClocks(dark: Bool) throws {
        let cities = [
            WorldCity(name: "Moscow", timeZone: "Europe/Moscow"),
            WorldCity(name: "Tokyo", timeZone: "Asia/Tokyo"),
        ]
        let item = ItemContent.worldClocks(cities, at: now, options: [ItemOption.showsTwoCities: "true"])
        try snapshot(item, module: .worldClocks, name: "clocks-two", dark: dark)
    }

    @Test(arguments: [true, false])
    func calendar(dark: Bool) throws {
        let standup = AgendaEvent(id: "1", title: "Standup", start: now, end: now)
        for (name, state) in [
            ("upcoming", CalendarItemState.upcoming(standup, startsIn: 1500)),
            ("current", .current(standup, endsIn: 900)),
            ("call", .callSoon(standup)),
        ] {
            var item = ItemContent(figure: ItemContent.calendarText(state, limit: 20), template: "")
            item.template = ItemContent.calendar([], at: now, options: [:]).template
            try snapshot(item, module: .calendar, name: "calendar-\(name)", dark: dark)
        }
    }

    @Test(arguments: [true, false])
    func eject(dark: Bool) throws {
        let volume = DiskVolume(
            name: "Backup", path: "/Volumes/Backup", total: 100, free: 50, isInternal: false, isEjectable: true
        )
        try snapshot(
            ItemContent.eject([volume, volume], ejecting: [], failures: [:], options: [:]),
            module: .eject, name: "eject-count", dark: dark
        )
        try snapshot(
            ItemContent.eject([volume], ejecting: [volume.path], failures: [:], options: [:]),
            module: .eject, name: "eject-ejecting", dark: dark
        )
        try snapshot(
            ItemContent.eject([volume], ejecting: [], failures: [volume.path: "In use by Finder"], options: [:]),
            module: .eject, name: "eject-failed", dark: dark
        )
    }

    @Test(arguments: [true, false])
    func gitMerge(dark: Bool) throws {
        var status = GitStatus()
        status.branch = "main"
        status.operation = .merge
        let reading = GitReading.repositories([GitRepository(path: "/dev/app", status: status)])
        try snapshot(ItemContent.git(reading, selected: nil), module: .git, name: "git-merge", dark: dark)
    }

    @Test(arguments: [true, false])
    func ejectPanelStates(dark: Bool) {
        let volumes = ["Backup", "Photos"].map {
            DiskVolume(name: $0, path: "/Volumes/\($0)", total: 100, free: 50, isInternal: false, isEjectable: true)
        }
        let list = VStack(alignment: .leading, spacing: 10) {
            EjectList(
                volumes: volumes,
                asksFirst: true,
                ejecting: ["/Volumes/Photos"],
                failures: ["/Volumes/Backup": "In use by Finder"]
            ) { _ in }
        }
        .padding(12)
        .frame(width: 320)
        snapshotPanel(list, name: "eject-states", dark: dark)
    }

    @Test(arguments: [true, false])
    func worldClocksPanel(dark: Bool) {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = EverydayStore(store: SnapshotStore(directory: folder))
        store.update {
            $0.cities = [
                WorldCity(name: "Dubai", timeZone: "Asia/Dubai"),
                WorldCity(name: "San Francisco", timeZone: "America/Los_Angeles"),
                WorldCity(name: "Delhi", timeZone: "Asia/Kolkata"),
            ]
        }
        let panel = WorldClocksPanel(monitor: SystemMonitor(everyday: store), fixedNow: now)
            .frame(width: 320)
        snapshotPanel(panel, name: "world-clocks", dark: dark)
    }

    @Test(arguments: [true, false])
    func gitPanelMerge(dark: Bool) {
        var status = GitStatus()
        status.branch = "main"
        status.operation = .merge
        let reading = GitReading.repositories([
            GitRepository(path: "/Users/dev/app", status: status, lastCommit: now.addingTimeInterval(-600)),
        ])
        snapshotPanel(GitPanel(reading: reading, selected: nil, manual: [], now: now), name: "git-merge", dark: dark)
    }
}
