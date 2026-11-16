import AppKit
import GlassWorkCore
import GlassWorkUI
import Observation
import SwiftUI

/// A nonactivating surface attached to the camera, including in full-screen Spaces.
@MainActor
final class IslandController {
    private let store: IslandStore
    private let actions: IslandActions
    private let statusItemsMinX: (NSScreen) -> CGFloat?
    private var panel: IslandPanel?
    private var hosting: IslandHostingView?
    private var surface: IslandView?
    private var currentGeometry: IslandGeometry?
    private var surfaceFrame = CGRect.zero
    private var targetFrame = CGRect.zero
    private var shrinkTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var pointerMonitor: Any?
    private var localPointerMonitor: Any?
    private var outsideMonitor: Any?
    private var localDismissMonitor: Any?
    private var escapeMonitor: Any?
    private var isEnabled = false
    private var pointerInside = false
    private var observationGeneration = 0

    init(store: IslandStore, actions: IslandActions, statusItemsMinX: @escaping (NSScreen) -> CGFloat?) {
        self.store = store
        self.actions = actions
        self.statusItemsMinX = statusItemsMinX
    }

    func apply(_ settings: IslandSettings) {
        // Every assignment redraws the island, so only a real change is written.
        if store.lifecycle.hoverToExpand != settings.expandsOnHover {
            store.lifecycle.hoverToExpand = settings.expandsOnHover
        }
        guard settings.isEnabled else {
            stop()
            return
        }
        if !isEnabled {
            isEnabled = true
            startObservers()
        }
        refresh()
    }

    func stop() {
        isEnabled = false
        observationGeneration += 1
        shrinkTask?.cancel()
        shrinkTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hosting = nil
        surface = nil
        surfaceFrame = .zero
        targetFrame = .zero
        pointerInside = false
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        for monitor in [pointerMonitor, localPointerMonitor, outsideMonitor, localDismissMonitor, escapeMonitor] {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        pointerMonitor = nil
        localPointerMonitor = nil
        outsideMonitor = nil
        localDismissMonitor = nil
        escapeMonitor = nil
        store.reset()
    }

    private func startObservers() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Event-driven hit testing allows transparent corners and animation padding to pass clicks through.
        // There is no pointer poll or periodic work while idle.
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePointer() }
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }
            return event
        }
    }

    private func observeStore() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = store.lifecycle
            _ = store.queue
            _ = store.page
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isEnabled, self.observationGeneration == generation else { return }
                self.refresh()
            }
        }
    }

    private func refresh() {
        guard isEnabled else { return }
        defer { observeStore() }
        // Without a notch, the screen with the menu bar: `NSScreen.main` follows keyboard focus.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        else {
            panel?.orderOut(nil)
            store.lifecycle.clickedOutside()
            updateDismissalMonitors()
            return
        }
        let geometry = Self.geometry(screen)
        currentGeometry = geometry
        // Public APIs do not expose the front app's menu bounds. Assume room on the left; never use
        // NSApp.mainMenu, which describes only our own menus. The collision input remains pluggable.
        let view = IslandView(
            store: store, geometry: geometry, actions: actions,
            statusItemsMinX: statusItemsMinX(screen), tracksHover: false
        )
        surface = view
        surfaceFrame = view.surfaceFrame(now: Date())
        updateDismissalMonitors()
        // A virtual notch has no idle hover target or visible peek.
        guard geometry.hasNotch || store.lifecycle.phase == .compact || store.lifecycle.phase == .expanded else {
            panel?.orderOut(nil)
            return
        }
        guard let panel = makePanelIfNeeded() else { return }
        // The outline's top ears extend ten points beyond the geometry's rectangle.
        let next = surfaceFrame.insetBy(dx: -10, dy: 0)
        if next != targetFrame {
            shrinkTask?.cancel()
            let union = panel.frame.union(next)
            let envelope = panel.isVisible
                ? CGRect(x: union.minX - 8, y: union.minY - 8, width: union.width + 16, height: union.height + 8)
                : next
            targetFrame = next
            place(view, geometry: geometry, frame: envelope)
            shrinkTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                // The newest view, not the one captured here: a refresh may have come in between.
                guard let self, !Task.isCancelled, isEnabled, let surface, let currentGeometry else { return }
                place(surface, geometry: currentGeometry, frame: next)
                updatePointer()
                shrinkTask = nil
            }
        } else {
            place(view, geometry: geometry, frame: panel.frame)
        }
        panel.orderFrontRegardless()
        updatePointer()
    }

    private func makePanelIfNeeded() -> IslandPanel? {
        if panel == nil {
            let window = IslandPanel()
            let host = IslandHostingView(rootView: AnyView(EmptyView()))
            host.onPointer = { [weak self] in self?.updatePointer() }
            host.sizingOptions = []
            window.contentView = host
            hosting = host
            panel = window
        }
        return panel
    }

    private func place(_ view: IslandView, geometry: IslandGeometry, frame: CGRect) {
        // The SwiftUI compact surface offsets unequal wings around the camera's center.
        hosting?.rootView = AnyView(
            view.fixedSize()
                .offset(x: geometry.notch.midX - frame.midX)
                .frame(width: frame.width, height: frame.height, alignment: .top)
        )
        panel?.setFrame(frame, display: true)
    }

    private func updatePointer() {
        guard isEnabled, let panel, panel.isVisible, let surface else { return }
        let inside = surface.contains(NSEvent.mouseLocation, in: surfaceFrame)
        panel.ignoresMouseEvents = !inside
        if !inside, store.lifecycle.phase == .expanded, store.lifecycle.nextDeadline == nil {
            store.lifecycle.pointerExited(at: Date())
        }
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            store.lifecycle.pointerEntered(at: Date())
        } else {
            store.lifecycle.pointerExited(at: Date())
        }
    }

    private func updateDismissalMonitors() {
        guard store.lifecycle.phase == .expanded else {
            for monitor in [outsideMonitor, localDismissMonitor, escapeMonitor] {
                if let monitor {
                    NSEvent.removeMonitor(monitor)
                }
            }
            outsideMonitor = nil
            localDismissMonitor = nil
            escapeMonitor = nil
            return
        }
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.clickedOutsideIfNeeded() }
            }
            localDismissMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .keyDown]
            ) { [weak self] event in
                MainActor.assumeIsolated {
                    if event.type == .keyDown, event.keyCode == 53 {
                        self?.store.lifecycle.escape()
                    } else if event.type != .keyDown {
                        self?.clickedOutsideIfNeeded()
                    }
                }
                return event
            }
        }
        if escapeMonitor == nil, Accessibility.isTrusted {
            escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                MainActor.assumeIsolated { self?.store.lifecycle.escape() }
            }
        }
    }

    private func clickedOutsideIfNeeded() {
        guard surface?.contains(NSEvent.mouseLocation, in: surfaceFrame) != true else { return }
        store.lifecycle.clickedOutside()
    }

    private static func geometry(_ screen: NSScreen) -> IslandGeometry {
        let menuHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return IslandGeometry(screen: IslandScreen(
            frame: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuHeight > 0 ? menuHeight : NSStatusBar.system.thickness
        ))
    }
}

@MainActor
private final class IslandHostingView: NSHostingView<AnyView> {
    var onPointer: (() -> Void)?
    private var pointerTracking: NSTrackingArea?

    override var needsPanelToBecomeKey: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking {
            removeTrackingArea(pointerTracking)
        }
        let area = NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseEntered(with _: NSEvent) {
        onPointer?()
    }

    override func mouseExited(with _: NSEvent) {
        onPointer?()
    }

    override func mouseMoved(with _: NSEvent) {
        onPointer?()
    }
}

@MainActor
private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
        frameRect
    }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        // Accessibility comes from IslandView's localized label and its card's children.
    }
}
