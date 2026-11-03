import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// GlassWork's own widgets: windows that sit on the desktop under other windows and update live.
@MainActor
final class DesktopWidgetController {
    private unowned let model: AppModel
    private var windows: [UUID: NSPanel] = [:]
    private var refresh: Timer?
    private let state = DesktopWidgetState()

    init(model: AppModel) {
        self.model = model
    }

    func apply(_ settings: WidgetSettings) {
        let wanted = Dictionary(uniqueKeysWithValues: settings.placements.map { ($0.id, $0) })
        for (id, window) in windows where wanted[id] == nil {
            window.close()
            windows[id] = nil
        }
        for placement in settings.placements where windows[placement.id] == nil {
            windows[placement.id] = makeWindow(placement)
        }
        refreshTimer(needed: !settings.placements.isEmpty)
    }

    private func refreshTimer(needed: Bool) {
        guard needed != (refresh != nil) else { return }
        refresh?.invalidate()
        refresh = nil
        guard needed else { return }
        update()
        refresh = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func update() {
        Task {
            state.snapshot = await model.monitor.widgetSnapshot()
            state.now = Date()
        }
    }

    private func makeWindow(_ placement: WidgetPlacement) -> NSPanel {
        let frame = CGRect(
            x: placement.x,
            y: placement.y,
            width: placement.size.width,
            height: placement.size.height
        )
        let window = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        let view = DesktopWidgetView(placement: placement, state: state) { [weak self] in
            self?.remove(placement)
        }
        window.contentView = NSHostingView(rootView: view.environment(\.panelActions, model.actions))
        window.orderFront(nil)
        return window
    }

    private func remove(_ placement: WidgetPlacement) {
        model.store.update { $0.widgets.placements.removeAll { $0.id == placement.id } }
    }
}

@MainActor
@Observable
final class DesktopWidgetState {
    var snapshot = WidgetSnapshot(date: .now)
    var now = Date()
}

struct DesktopWidgetView: View {
    let placement: WidgetPlacement
    let state: DesktopWidgetState
    let remove: () -> Void

    var body: some View {
        WidgetFace(kind: placement.kind, size: placement.size, snapshot: state.snapshot, now: state.now)
            .padding(16)
            .frame(width: placement.size.width, height: placement.size.height)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .contextMenu {
                Button(loc("Remove"), role: .destructive, action: remove)
            }
    }
}
