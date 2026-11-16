import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct AIUsageMenuBarFigureTests {
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
    func aiUsageBothWindows(dark: Bool) throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reading = AIUsageReading(
            tools: [AIToolUsage(tool: .codex, windows: [
                AIWindow(kind: .fiveHour, used: 0.42, resetsAt: now.addingTimeInterval(3600)),
                AIWindow(kind: .week, used: 0.17, resetsAt: now.addingTimeInterval(86400)),
            ])],
            readAt: now
        )
        try snapshot(ItemContent.aiUsage(reading, at: now), module: .aiUsage, name: "ai-usage-both", dark: dark)
    }
}
