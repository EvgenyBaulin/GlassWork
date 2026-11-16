import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// The shelf in the Dock: its tile empty and with files, and its card, in both themes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockShelfSnapshotTests {
    /// Real files, because the shelf drops what it cannot find.
    private func monitor(filled: Bool) async throws -> SystemMonitor {
        let store = ShelfStore(folder: sampleFolder())
        if filled {
            let folder = sampleFolder()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var urls: [URL] = []
            for (name, size) in [("Screenshot 14:02.png", 1_200_000), ("invoice-oct.pdf", 340_000), (
                "notes.md",
                4000
            )] {
                let url = folder.appending(path: name, directoryHint: .notDirectory)
                try Data(repeating: 0, count: size).write(to: url)
                urls.append(url)
            }
            await store.add(urls.reversed(), at: Date(timeIntervalSince1970: 1_800_000_000))
        }
        return SystemMonitor(shelf: store)
    }

    @Test(arguments: [true, false])
    func tileEmpty(dark: Bool) async throws {
        let tile = try await WidgetTile(module: .shelf, size: 56, monitor: monitor(filled: false), click: {}, hold: {})
        assertPanel(tile.padding(8), width: 72, height: 72, dark: dark, name: "dock-shelf-tile-empty")
    }

    @Test(arguments: [true, false])
    func tileWithFiles(dark: Bool) async throws {
        let tile = try await WidgetTile(module: .shelf, size: 56, monitor: monitor(filled: true), click: {}, hold: {})
        assertPanel(tile.padding(8), width: 72, height: 72, dark: dark, name: "dock-shelf-tile-files")
    }

    @Test(arguments: [true, false])
    func cardWithFiles(dark: Bool) async throws {
        let card = try await DockShelfCard(store: monitor(filled: true).shelf)
        assertPanel(card, dark: dark, name: "dock-shelf-card")
    }

    @Test(arguments: [true, false])
    func emptyCard(dark: Bool) async throws {
        let card = try await DockShelfCard(store: monitor(filled: false).shelf)
        assertPanel(card, dark: dark, name: "dock-shelf-card-empty")
    }
}
