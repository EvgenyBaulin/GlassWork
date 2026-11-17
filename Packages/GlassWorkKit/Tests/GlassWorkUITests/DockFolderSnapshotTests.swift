import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DockFolderSnapshotTests {
    private let apps = (0 ..< 4).map { DockApp(path: "/Applications/Sample \($0).app", name: "Sample \($0)") }

    private func folder(symbol: String? = nil, emoji: String? = nil, tint: FolderTint? = nil) -> AppFolder {
        var folder = AppFolder(name: "Work", apps: apps)
        folder.symbol = symbol
        folder.emoji = emoji
        folder.tint = tint
        return folder
    }

    private var tiles: some View {
        let variants = [
            folder(),
            folder(symbol: "briefcase.fill", tint: .orange),
            folder(emoji: "🚀", tint: .purple),
            folder(symbol: "star.fill"),
        ]
        return HStack(spacing: 12) {
            ForEach(variants.indices, id: \.self) { index in
                FolderTile(folder: variants[index], size: 64, isRunning: false) {}
            }
        }
        .padding(16)
    }

    @Test(arguments: [true, false])
    func tileWithSymbolEmojiAndTint(dark: Bool) {
        snapshotPanel(tiles, name: "folder-tiles", dark: dark)
    }

    @Test(arguments: [true, false])
    func card(dark: Bool) {
        let view = FolderCard(
            folder: folder(symbol: "briefcase.fill", tint: .teal),
            actions: DockActions(
                open: { _ in },
                clickWidget: { _ in },
                holdWidget: { _ in },
                update: { _ in },
                needsSpace: { _ in }
            ),
            close: {}
        )
        .padding(20)
        snapshotPanel(view, name: "folder-card", dark: dark)
    }
}
