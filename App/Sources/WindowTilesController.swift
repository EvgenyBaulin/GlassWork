import AppKit
import GlassWorkCore
import GlassWorkUI
import Observation
import SwiftUI

/// Sends the front window to a place on the screen from the keyboard.
///
/// Nothing runs until Window Tiles is turned on in Settings. It only ever checks for Accessibility: the macOS
/// dialog is never raised from here, the page and the message point to System Settings instead.
@MainActor
final class WindowTilesController {
    /// A move waiting for its preview to be seen.
    private struct PendingMove {
        let window: FrontWindow
        let plan: TilePlan
    }

    /// Long enough to see where the window goes, short enough not to feel like waiting.
    private static let previewLead = Duration.milliseconds(200)
    /// The zone stays a moment after the window arrives.
    private static let previewLinger = Duration.milliseconds(150)

    private unowned let model: AppModel
    private var isRunning = false
    private var memory: TileMemory?
    private var pending: PendingMove?
    private var preview: GlassPanel?
    private var previewTask: Task<Void, Never>?
    private var notice: GlassPanel?
    private var noticeTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        for command in TileCommand.all {
            model.shortcuts.bind(.tile(command)) { [weak self] in self?.perform(command) }
        }
    }

    /// Runs on every settings change, so it only acts when the switch itself moved.
    func apply(_ settings: WindowTilesSettings) {
        guard settings.isEnabled != isRunning else { return }
        isRunning = settings.isEnabled
        for command in TileCommand.all {
            model.shortcuts.setActive(.tile(command), settings.isEnabled)
        }
        if !settings.isEnabled {
            stop()
        }
    }

    private func stop() {
        memory = nil
        pending = nil
        closePreview()
    }

    private func perform(_ command: TileCommand) {
        // A press during a preview goes on from where the window was about to land.
        finishPendingMove()
        closePreview()
        guard Accessibility.isTrusted else {
            show(.needsAccessibility)
            return
        }
        let height = primaryHeight
        guard let window = FrontWindow.current(primaryHeight: height) else {
            show(.noWindow)
            return
        }
        guard !window.isFullScreen else {
            show(.fullScreen)
            return
        }
        guard window.canMove, let frame = window.frame else {
            show(.cannotMove)
            return
        }
        guard let plan = TilePlanner(displays: displays).plan(
            command,
            window: frame,
            app: window.app,
            memory: memory
        ) else {
            show(.oneDisplay)
            return
        }
        run(PendingMove(window: window, plan: plan), command: command)
    }

    private func run(_ move: PendingMove, command: TileCommand) {
        guard model.store.settings.windowTiles.showsPreview else {
            finish(move)
            return
        }
        pending = move
        let shortcut = model.store.settings.shortcuts.shortcut(for: .tile(command))?.label ?? ""
        showPreview(title: command.title(for: move.plan), shortcut: shortcut, frame: move.plan.frame)
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: Self.previewLead)
            guard !Task.isCancelled else { return }
            self?.finishPendingMove()
            try? await Task.sleep(for: Self.previewLinger)
            guard !Task.isCancelled else { return }
            self?.closePreview()
        }
    }

    private func finishPendingMove() {
        guard let move = pending else { return }
        pending = nil
        finish(move)
    }

    private func finish(_ move: PendingMove) {
        let plan = move.plan
        let landed = move.window.place(plan.frame, in: plan.display.visibleFrame)
        memory = zip(plan.tile, landed).map { TileMemory(app: move.window.app, tile: $0, frame: $1) }
    }

    /// The display with the menu bar: the "main" screen follows the keyboard focus and is not the origin.
    private var primaryHeight: Double {
        NSScreen.screens.first.map { Double($0.frame.height) } ?? 0
    }

    private var displays: [TileDisplay] {
        let dock = model.store.settings.dock
        return NSScreen.screens.enumerated().map { index, screen in
            let display = TileDisplay(frame: screen.frame, visibleFrame: screen.visibleFrame)
            // GlassWork's Dock stands on the primary display only.
            guard index == 0 else { return display }
            return display.reserving(DockBarLayout.reservedDepth(dock), at: dock.position)
        }
    }

    private func showPreview(title: String, shortcut: String, frame: CGRect) {
        let hosting = NSHostingView(rootView: WindowTilesPreview(title: title, shortcut: shortcut))
        // The window's size is the zone. Left to the content it would shrink around the label.
        hosting.sizingOptions = []
        let window = GlassPanel()
        window.contentView = hosting
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.setFrame(frame, display: false)
        // Not key: the window being moved has to keep the keyboard.
        window.orderFrontRegardless()
        preview = window
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        preview?.close()
        preview = nil
    }

    private func show(_ message: WindowTilesNotice) {
        noticeTask?.cancel()
        notice?.close()
        let hosting = NSHostingView(rootView: WindowTilesNoticeHUD(notice: message).modifier(PanelGlass()))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = GlassPanel()
        window.contentView = hosting
        window.ignoresMouseEvents = true
        window.setFrame(Self.noticeFrame(size: hosting.fittingSize), display: false)
        window.orderFrontRegardless()
        notice = window
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: message.duration)
            guard !Task.isCancelled else { return }
            self?.notice?.close()
            self?.notice = nil
        }
    }

    /// Low on the screen the cursor is on, where the system shows its own volume message.
    private static func noticeFrame(size: CGSize) -> CGRect {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? .zero
        return CGRect(
            x: visible.midX - size.width / 2,
            y: visible.minY + visible.height * 0.15,
            width: size.width,
            height: size.height
        )
    }
}

/// Both values or nothing.
private func zip<First, Second>(_ first: First?, _ second: Second?) -> (First, Second)? {
    guard let first, let second else { return nil }
    return (first, second)
}
