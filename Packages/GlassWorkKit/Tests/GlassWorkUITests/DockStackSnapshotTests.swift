import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Every file here is made up: icons come from the file's type, so no test reads a real folder.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockStackSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let apps = (0 ..< 4).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }

    private var actions: DockActions {
        DockActions(open: { _ in }, clickWidget: { _ in }, holdWidget: { _ in }, update: { _ in }, needsSpace: { _ in })
    }

    private var downloads: DockStack {
        var stack = DockStack(path: "/made/up/Downloads", name: "Downloads")
        stack.isDownloads = true
        return stack
    }

    private var documents: DockStack {
        DockStack(path: "/made/up/Documents", name: "Documents")
    }

    private var files: [DockFile] {
        [
            DockFile(
                path: "/made/up/a.dmg.crdownload",
                name: "pocket-api-1.4.2.dmg",
                size: 41_000_000,
                added: now,
                isDownloading: true,
                progress: 0.62
            ),
            DockFile(
                path: "/made/up/b.png",
                name: "Screenshot 14-02.png",
                size: 1_200_000,
                added: now.addingTimeInterval(-60)
            ),
            DockFile(
                path: "/made/up/c.pdf",
                name: "invoice-oct.pdf",
                size: 340_000,
                added: now.addingTimeInterval(-3600)
            ),
            DockFile(
                path: "/made/up/d.zip",
                name: "glasswork-spec.zip",
                size: 4_800_000,
                added: now.addingTimeInterval(-90000)
            ),
            DockFile(path: "/made/up/e", name: "Archive", added: now.addingTimeInterval(-99000), isFolder: true),
        ]
    }

    private func card(_ stack: DockStack, files: [DockFile], position: DockPosition = .bottom) -> some View {
        StackCard(stack: stack, files: files, position: position, actions: actions, now: now) {}
            .padding(12)
    }

    @Test(arguments: [true, false])
    func downloadsCard(dark: Bool) {
        snapshotPanel(card(downloads, files: files), name: "downloads", dark: dark)
    }

    @Test(arguments: [true, false])
    func noDownloadsYet(dark: Bool) {
        snapshotPanel(card(downloads, files: []), name: "downloads-empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func stackAsAGrid(dark: Bool) {
        snapshotPanel(card(documents, files: files), name: "grid", dark: dark)
    }

    @Test(arguments: [true, false])
    func anEmptyStack(dark: Bool) {
        snapshotPanel(card(documents, files: []), name: "grid-empty", dark: dark)
    }

    @Test(arguments: [true, false])
    func stackAsAFan(dark: Bool) {
        var fan = documents
        fan.style = .fan
        snapshotPanel(card(fan, files: files).padding(.trailing, 60), name: "fan", dark: dark)
    }

    /// A fan would run off the screen at a side, so it opens as a grid there.
    @Test(arguments: [true, false])
    func aFanAtTheSideIsAGrid(dark: Bool) {
        var fan = documents
        fan.style = .fan
        snapshotPanel(card(fan, files: files, position: .left), name: "fan-side", dark: dark)
    }

    @Test(arguments: [true, false])
    func tiles(dark: Bool) {
        let row = HStack(spacing: 8) {
            StackTile(stack: documents, files: [], size: 48) {}
            StackTile(stack: downloads, files: [], size: 48) {}
            StackTile(stack: downloads, files: files, size: 48) {}
        }
        .padding(8)
        snapshotPanel(row, name: "tiles", dark: dark)
    }

    private func bar(page: Int, available: Double) -> some View {
        var settings = DockSettings()
        settings.iconSize = 48
        settings.items = apps.map(DockItem.app)
            + [.widget(.cpu), .widget(.memory), .widget(.disk), .widget(.network), .widget(.gpu), .widget(.sensors)]
            + [.stack(downloads)]
        let state = DockLiveState(settings: settings)
        state.available = available
        state.page = page
        let size = DockBarLayout.windowSize(
            for: .rest,
            count: state.arrangement.slots.count,
            settings: state.fittedSettings
        )
        return DockView(state: state, monitor: SystemMonitor(), actions: actions)
            .frame(width: size.width, height: size.height)
    }

    /// The first set has only the button onward, and the dividers fall between the groups.
    @Test(arguments: [true, false])
    func firstSetOfWidgets(dark: Bool) {
        snapshotPanel(bar(page: 0, available: 600), name: "page-1", dark: dark)
    }

    @Test(arguments: [true, false])
    func lastSetOfWidgets(dark: Bool) {
        snapshotPanel(bar(page: 2, available: 600), name: "page-last", dark: dark)
    }

    @Test(arguments: [true, false])
    func everythingFitsWithDividers(dark: Bool) {
        snapshotPanel(bar(page: 0, available: .infinity), name: "all", dark: dark)
    }
}
