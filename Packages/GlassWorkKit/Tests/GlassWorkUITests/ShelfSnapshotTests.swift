import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The shelf panel empty and with files, and its menu bar item, in both themes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct ShelfSnapshotTests {
    /// Real files, because the shelf drops what it cannot find. Thumbnails are off so no image loads late.
    private func store(filled: Bool) async throws -> ShelfStore {
        let store = ShelfStore(folder: sampleFolder())
        var settings = ShelfSettings()
        settings.showsThumbnails = false
        store.apply(settings)
        guard filled else { return store }
        let folder = sampleFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, size) in [("build-1.4.zip", 4_000_000), ("release-notes.txt", 2000), ("invoice-oct.pdf", 280_000)] {
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            try Data(repeating: 0, count: size).write(to: url)
            urls.append(url)
        }
        await store.add(urls, at: Date(timeIntervalSince1970: 1_800_000_000))
        return store
    }

    @Test(arguments: [true, false])
    func emptyPanelIsADropZone(dark: Bool) async throws {
        try await assertPanel(ShelfPanel(store: store(filled: false)), dark: dark, name: "shelf-empty")
    }

    @Test(arguments: [true, false])
    func panelWithFiles(dark: Bool) async throws {
        try await assertPanel(ShelfPanel(store: store(filled: true)), dark: dark, name: "shelf-files")
    }

    @Test(arguments: [true, false])
    func menuBarItem(dark: Bool) async throws {
        for (filled, name) in [(true, "shelf-item-count"), (false, "shelf-item-empty")] {
            let monitor = try await SystemMonitor(shelf: store(filled: filled))
            assertItem(monitor: monitor, dark: dark, name: name)
        }
    }

    private func assertItem(monitor: SystemMonitor, dark: Bool, name: String) {
        let renderer = MenuBarItemRenderer(module: .shelf, style: .figure, numbers: .compact, monitor: monitor)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let width = MenuBarItemView.width(module: .shelf, style: .figure, numbers: .compact, monitor: monitor)
        let view = NSImageView(frame: CGRect(x: 0, y: 0, width: width, height: 24))
        view.image = renderer.image(size: CGSize(width: width, height: 24), force: true)
        view.contentTintColor = .labelColor
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }
}

@MainActor
struct ShelfItemContentTests {
    @Test func countsFilesAndDimsWhenEmpty() async throws {
        let store = ShelfStore(folder: sampleFolder())
        #expect(ItemContent.shelf(store).figure == "0")
        #expect(ItemContent.shelf(store).isDimmed)
        let folder = sampleFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "a.txt", directoryHint: .notDirectory)
        try Data([1]).write(to: url)
        await store.add([url])
        #expect(ItemContent.shelf(store).figure == "1")
        #expect(!ItemContent.shelf(store).isDimmed)
    }
}
