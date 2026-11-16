import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct MenuBarFigureSnapshotTests {
    private func snapshot(_ content: ItemContent, module: ModuleID, name: String, dark: Bool) throws {
        let renderer = MenuBarItemRenderer(module: module, style: .figure, numbers: .compact, monitor: SystemMonitor())
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let font = NSFont.monospacedDigitSystemFont(ofSize: content.secondLine == nil ? 12 : 9, weight: .medium)
        let textWidth = content
            .figureWidth ?? ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
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

    @Test(arguments: [true, false])
    func memoryShareAndSwap(dark: Bool) throws {
        let sample = MemorySample(
            total: 32_000_000_000, app: 10_000_000_000, wired: 2_000_000_000, compressed: 0,
            cached: 0, free: 0, swapUsed: 1_500_000_000, swapTotal: 2_000_000_000, pressure: .warning
        )
        for style in [NumberStyle.compact, .precise] {
            let item = ItemContent.memory(
                sample, style: style, options: [ItemOption.memoryFigure: MemoryFigure.shareAndSwap.rawValue]
            )
            try snapshot(item, module: .memory, name: "share-swap-\(style)", dark: dark)
        }
    }

    @Test(arguments: [true, false])
    func diskFreePercent(dark: Bool) throws {
        for free in [UInt64(250), 50] {
            let volume = DiskVolume(
                name: "Macintosh HD", path: "/", total: 1000, free: free, isInternal: true, isEjectable: false
            )
            let item = ItemContent.disk(
                volume, activity: nil, style: .compact,
                options: [ItemOption.diskFigure: DiskFigure.freePercent.rawValue]
            )
            try snapshot(item, module: .disk, name: "free-\(free)", dark: dark)
        }
    }

    @Test(arguments: [true, false])
    func networkOfflineAndIdle(dark: Bool) throws {
        let counters = [InterfaceCounters(name: "en0", received: 100, sent: 10)]
        let idle = NetworkSample.between(counters, counters, seconds: 2)
        let offline = NetworkSample.between(counters, [], seconds: 2)
        for (name, sample) in [("idle", idle), ("offline", offline)] {
            try snapshot(
                ItemContent.network(sample, style: .compact, options: [:]),
                module: .network,
                name: name,
                dark: dark
            )
        }
    }

    @Test(arguments: [true, false])
    func oneDevServer(dark: Bool) throws {
        let server = DevServer(port: 5173, pid: 1, process: "node", project: "web", kind: .web)
        try snapshot(ItemContent.devServers(.servers([server])), module: .devServers, name: "port", dark: dark)
    }

    @Test(arguments: [true, false])
    func notesPreviewAndEmpty(dark: Bool) throws {
        for (name, note) in [("preview", "Ship the update and check the changelog\nTomorrow"), ("empty", "")] {
            try snapshot(ItemContent.notes(note), module: .notes, name: name, dark: dark)
        }
    }
}
