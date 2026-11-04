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
    private var snapTask: Task<Void, Never>?

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
        let view = DesktopWidgetView(
            placement: placement,
            state: state,
            remove: { [weak self] in self?.remove(placement) },
            resize: { [weak self] size in self?.resize(placement, to: size) },
            toggleLock: { [weak self] in self?.toggleLock(placement) },
            openPanel: { [weak self] in self?.openPanel(placement) }
        )
        window.contentView = NSHostingView(rootView: view.environment(\.panelActions, model.actions))
        window.isMovableByWindowBackground = !placement.isLocked
        window.orderFront(nil)
        observeMoves(of: window, placement: placement)
        return window
    }

    /// Dragged widgets land on the grid; ⌥ keeps them exactly where they were dropped.
    private func observeMoves(of window: NSPanel, placement: WidgetPlacement) {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.moved(window, id: placement.id)
            }
        }
    }

    private func moved(_ window: NSPanel, id: UUID) {
        guard NSEvent.pressedMouseButtons == 0 else {
            scheduleSnap(window, id: id)
            return
        }
        scheduleSnap(window, id: id)
    }

    private func scheduleSnap(_ window: NSPanel, id: UUID) {
        snapTask?.cancel()
        snapTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let window, NSEvent.pressedMouseButtons == 0 else { return }
            commit(window, id: id)
        }
    }

    private func commit(_ window: NSPanel, id: UUID) {
        var origin = window.frame.origin
        if !NSEvent.modifierFlags.contains(.option) {
            origin = CGPoint(x: WidgetPlacement.snapped(origin.x), y: WidgetPlacement.snapped(origin.y))
            window.setFrameOrigin(origin)
        }
        model.store.update { settings in
            guard let index = settings.widgets.placements.firstIndex(where: { $0.id == id }) else { return }
            settings.widgets.placements[index].x = origin.x
            settings.widgets.placements[index].y = origin.y
        }
    }

    private func resize(_ placement: WidgetPlacement, to size: WidgetSize) {
        windows.removeValue(forKey: placement.id)?.close()
        model.store.update { settings in
            guard let index = settings.widgets.placements.firstIndex(where: { $0.id == placement.id }) else { return }
            settings.widgets.placements[index].size = size
        }
    }

    private func toggleLock(_ placement: WidgetPlacement) {
        windows[placement.id]?.isMovableByWindowBackground.toggle()
        model.store.update { settings in
            guard let index = settings.widgets.placements.firstIndex(where: { $0.id == placement.id }) else { return }
            settings.widgets.placements[index].isLocked.toggle()
        }
    }

    private func openPanel(_ placement: WidgetPlacement) {
        guard let frame = windows[placement.id]?.frame else { return }
        model.showPanel(placement.kind.module, beside: frame)
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
    let resize: (WidgetSize) -> Void
    let toggleLock: () -> Void
    let openPanel: () -> Void
    @State private var isHovered = false

    var body: some View {
        WidgetFace(kind: placement.kind, size: placement.size, snapshot: state.snapshot, now: state.now)
            .padding(16)
            .frame(width: placement.size.width, height: placement.size.height)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    controls
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture(perform: openPanel)
            .contextMenu { menu }
    }

    private var controls: some View {
        HStack(spacing: 4) {
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            Button(action: openPanel) {
                Image(systemName: "arrow.up.right")
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: .semibold))
        .padding(8)
    }

    @ViewBuilder
    private var menu: some View {
        Picker(loc("Size"), selection: Binding(get: { placement.size }, set: resize)) {
            Text("S").tag(WidgetSize.small)
            Text("M").tag(WidgetSize.medium)
            Text("L").tag(WidgetSize.large)
            Text("XL").tag(WidgetSize.extraLarge)
        }
        Button(placement.isLocked ? loc("Unlock Position") : loc("Lock Position"), action: toggleLock)
        Divider()
        Button(loc("Remove"), role: .destructive, action: remove)
    }
}
