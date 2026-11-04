import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// Borderless panels refuse the keyboard, and a card has fields to type in. It takes it only when one is clicked.
private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}

/// Shows GlassWork's Dock and hides the system one while it runs.
///
/// Nothing here runs until the owner turns the Dock on in Settings.
@MainActor
final class DockController {
    private unowned let model: AppModel
    private let state = DockLiveState()
    private var window: NSPanel?
    private var screens: NSObjectProtocol?
    private var workspace: [NSObjectProtocol] = []
    private var tracker = DockLaunchTracker()
    private var expiry: Task<Void, Never>?
    private var bundleIDs: [String: String] = [:]
    /// What the view asked for.
    private var requested = DockSpace.rest
    /// What the window is sized for.
    private var space = DockSpace.rest
    private var shrink: Task<Void, Never>?
    /// False while a Dock that hides itself is out of sight.
    private var isRevealed = true
    private lazy var pointerWatcher = DockPointerWatcher { [weak self] in self?.updateReveal() }
    private var hiding: Task<Void, Never>?
    private var cardDismissal: TransientDismissal?
    private lazy var folders = DockFolders { [weak self] in self?.state.files = $0 }

    /// Long enough for icons to settle before the window closes in around them.
    private static let shrinkDelay = Duration.milliseconds(300)

    init(model: AppModel) {
        self.model = model
    }

    func apply(_ settings: DockSettings) {
        guard settings.isEnabled else {
            close()
            return
        }
        if window == nil {
            SystemDock.hide()
            isRevealed = !settings.autoHides
            open()
        }
        state.settings = settings
        watchPointer(settings.autoHides)
        folders.watch(settings.foldersToRead)
        refreshRunning()
        place()
        updateReveal()
    }

    /// Runs on quit, and the saved values also restore after a crash on the next launch.
    func restoreSystemDock() {
        SystemDock.restore()
    }

    private func open() {
        let panel = DockPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .dock
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        // Hide Others in any app counts this app too now that it has a Dock icon.
        panel.canHide = false
        let hosting = NSHostingView(rootView: DockView(state: state, monitor: model.monitor, actions: actions))
        // The window's size is decided here. Left to the content it would grow from its corner, sideways.
        hosting.sizingOptions = []
        panel.contentView = hosting
        window = panel
        screens = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        observeApps()
    }

    private func observeApps() {
        let center = NSWorkspace.shared.notificationCenter
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification]
        workspace = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
    }

    /// Restores even with no window, so a Dock left hidden by a crash comes back once it is turned off.
    private func close() {
        if let window, model.hasCard(from: window) {
            model.closePanels()
        }
        shrink?.cancel()
        watchPointer(false)
        folders.watch([])
        state.openCard = nil
        state.page = 0
        updateCardDismissal(isOpen: false)
        isRevealed = true
        if let screens {
            NotificationCenter.default.removeObserver(screens)
        }
        screens = nil
        workspace.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspace = []
        expiry?.cancel()
        tracker = DockLaunchTracker()
        state.launching = []
        window?.close()
        window = nil
        requested = .rest
        space = .rest
        SystemDock.restore()
    }

    /// The Dock stays while a card it opened is up, and goes once it closes.
    func cardsChanged() {
        updateReveal()
    }

    private func click(_ module: ModuleID) {
        let monitor = model.monitor
        let context = DockWidgetContext(
            timers: monitor.everyday.data.timers,
            devServers: monitor.developer.devServers,
            events: monitor.agenda.events
        )
        switch DockWidgetClick.resolve(module, context: context, at: Date()) {
        case .showCard: toggleCard(module)
        case let .perform(action): model.perform(action)
        case .toggleStopwatch: monitor.everyday.update { $0.stopwatch.toggle(at: Date()) }
        case .toggleKeepAwake: monitor.everyday.toggleKeepAwake()
        case .togglePlayback: monitor.nowPlaying.perform(.toggle)
        case let .open(url): NSWorkspace.shared.open(url)
        }
    }

    private func toggleCard(_ module: ModuleID) {
        guard module.hasDockCard, let window, let screen else { return }
        let settings = state.settings
        let bar = frame(for: .rest, on: screen)
        let pointer = NSEvent.mouseLocation
        model.toggleCard(module, from: window) { size in
            DockBarLayout.cardFrame(
                size: size,
                pointer: pointer,
                bar: bar,
                settings: settings,
                visible: screen.visibleFrame
            )
        }
    }

    private var actions: DockActions {
        DockActions(
            open: { [weak self] app in
                self?.model.closePanels()
                self?.launch(app)
            },
            clickWidget: { [weak self] in self?.click($0) },
            holdWidget: { [weak self] in self?.toggleCard($0) },
            update: { [weak self] change in
                self?.model.store.update { $0.dock.items = change($0.dock.items) }
            },
            needsSpace: { [weak self] space in
                self?.requested = space
                self?.updateCardDismissal(isOpen: space == .folder)
                self?.updateSpace()
            },
            commands: { [weak self] in self?.commands(for: $0) ?? [] },
            perform: { [weak self] in self?.perform($0, on: $1) },
            turnPage: { [weak self] in self?.turnPage(by: $0) },
            openFile: { NSWorkspace.shared.open(URL(filePath: $0)) },
            showFolder: { NSWorkspace.shared.open(URL(filePath: $0, directoryHint: .isDirectory)) },
            change: { [weak self] change in self?.model.store.update { change(&$0.dock) } },
            presets: { [weak self] in self?.presets ?? [] },
            applyPreset: { [weak self] in self?.apply($0) },
            savePreset: { [weak self] in self?.savePreset() },
            openSettings: { [weak self] in self?.model.showMainWindow(.dock) }
        )
    }

    private var presets: [DockPreset] {
        DockPresets.offered(in: state.settings)
    }

    private func apply(_ preset: DockPreset) {
        let current = presets.first { $0.id == state.settings.activePreset }
        model.store.update { DockPresets.apply(preset, current: current, to: &$0.dock) }
    }

    /// Asks for a name in a dialog of the app's own, which needs no permission.
    private func savePreset() {
        let alert = NSAlert()
        alert.messageText = loc("Save Current as Preset")
        alert.addButton(withTitle: loc("Save"))
        alert.addButton(withTitle: loc("Cancel"))
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = loc("Preset name")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        let name = field.stringValue
        model.store.update { settings in
            let preset = DockPresets.capture(settings.dock, id: UUID().uuidString, name: name)
            DockPresets.store(preset, in: &settings.dock)
            settings.dock.activePreset = preset.id
        }
    }

    private func turnPage(by count: Int) {
        state.page = max(state.arrangement.page + count, 0)
        place()
    }

    /// A card closes on Esc, on a click anywhere else, and when another app comes forward.
    private func updateCardDismissal(isOpen: Bool) {
        guard isOpen != (cardDismissal != nil) else { return }
        cardDismissal?.stop()
        cardDismissal = nil
        guard isOpen, let window else { return }
        let dismissal = TransientDismissal(panel: window) { [weak self] in self?.state.openCard = nil }
        dismissal.start()
        cardDismissal = dismissal
    }

    private func runningApp(_ app: DockApp) -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        return apps.first { running in
            let bundleID = bundleIDs[app.path]
            return (bundleID != nil && running.bundleIdentifier == bundleID)
                || running.bundleURL?.path(percentEncoded: false) == app.path
        }
    }

    private func target(of running: NSRunningApplication) -> QuitTarget {
        QuitTarget(
            pid: running.processIdentifier,
            name: running.localizedName ?? "",
            bundleID: running.bundleIdentifier,
            path: running.bundleURL?.path(percentEncoded: false)
        )
    }

    private func commands(for app: DockApp) -> [DockAppCommand] {
        let running = runningApp(app)
        let canQuit = running.map { !QuitPolicy.isProtected(target(of: $0)) } ?? false
        return DockAppCommand.offered(isRunning: running != nil, canQuit: canQuit)
    }

    private func perform(_ command: DockAppCommand, on app: DockApp) {
        let running = runningApp(app)
        switch command {
        case .open: launch(app)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: app.path)])
        case .showAllWindows: running?.activate(options: .activateAllWindows)
        case .hide: running?.hide()
        case .hideOthers: hideOthers(than: running)
        case .quit, .forceQuit:
            if let running {
                model.quit(target(of: running), force: command == .forceQuit)
            }
        }
    }

    private func hideOthers(than kept: NSRunningApplication?) {
        kept?.activate()
        let own = NSRunningApplication.current
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0 != kept && $0 != own
        }
        others.forEach { $0.hide() }
    }

    /// Grows at once, so nothing is cut off. Shrinks late, so nothing is cut off on the way down either.
    private func updateSpace() {
        shrink?.cancel()
        // A bouncing icon rises above the bar, wherever the pointer has gone.
        let wanted = max(requested, state.launching.isEmpty ? .rest : .magnified)
        updateReveal()
        if wanted >= space {
            space = wanted
            place()
        } else {
            shrink = Task { [weak self] in
                try? await Task.sleep(for: Self.shrinkDelay)
                guard let self, !Task.isCancelled else { return }
                space = wanted
                place()
            }
        }
    }

    /// Bounces from the click until the app is up, and stops at once if it cannot start.
    private func launch(_ app: DockApp) {
        let url = URL(filePath: app.path)
        guard url.pathExtension == "app" else {
            NSWorkspace.shared.open(url)
            return
        }
        tracker.begin(app.path, isRunning: state.running.contains(app.path), at: Date())
        showLaunches()
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { [weak self] _, error in
            let failed = error != nil
            Task { @MainActor in self?.launchReturned(app.path, failed: failed) }
        }
    }

    private func launchReturned(_ path: String, failed: Bool) {
        if failed {
            tracker.fail(path)
        }
        refreshRunning()
    }

    /// An app that is still starting counts only once it has finished: that is when bouncing stops.
    private func refreshRunning() {
        let apps = state.settings.apps
        for app in apps where bundleIDs[app.path] == nil {
            bundleIDs[app.path] = Bundle(path: app.path)?.bundleIdentifier
        }
        let running = NSWorkspace.shared.runningApplications.filter(\.isFinishedLaunching).map {
            RunningApp(bundleID: $0.bundleIdentifier, path: $0.bundleURL?.path(percentEncoded: false))
        }
        state.running = DockRunningApps.match(apps, bundleIDs: bundleIDs, running: running)
        tracker.update(running: state.running, at: Date())
        showLaunches()
    }

    private func showLaunches() {
        state.launching = tracker.launching
        updateSpace()
        expiry?.cancel()
        guard let deadline = tracker.nextDeadline else { return }
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(deadline.timeIntervalSinceNow))
            guard let self, !Task.isCancelled else { return }
            refreshRunning()
        }
    }

    /// Always the screen with the menu bar: the "main" screen follows the keyboard focus and would make
    /// the Dock hop between displays.
    private var screen: NSScreen? {
        NSScreen.screens.first
    }

    private func frame(for space: DockSpace, on screen: NSScreen, isRevealed: Bool = true) -> CGRect {
        let settings = state.fittedSettings
        let count = state.arrangement.slots.count
        return DockBarLayout.windowFrame(
            size: DockBarLayout.windowSize(for: space, count: count, settings: settings),
            position: settings.position,
            screen: screen.frame,
            topInset: screen.frame.maxY - screen.visibleFrame.maxY,
            isRevealed: isRevealed
        )
    }

    /// A hidden Dock leaves the screen list as well: the frame alone could land on a neighbouring display.
    private func place(sliding: Bool = false) {
        guard let window, let screen else { return }
        measureRoom(on: screen)
        let target = frame(for: space, on: screen, isRevealed: isRevealed)
        if isRevealed {
            window.orderFront(nil)
        }
        if sliding, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DockAutoHide.slideDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.leaveScreenIfHidden() }
            }
            return
        }
        if window.frame != target {
            window.setFrame(target, display: true)
        }
        leaveScreenIfHidden()
    }

    /// A side Dock has only what is left below the menu bar.
    private func measureRoom(on screen: NSScreen) {
        let length = state.settings.position.isVertical ? screen.visibleFrame.height : screen.frame.width
        let room = length - 2 * DockBarLayout.screenGap
        if state.available != room {
            state.available = room
        }
    }

    private func leaveScreenIfHidden() {
        if !isRevealed {
            window?.orderOut(nil)
        }
    }

    private func watchPointer(_ wanted: Bool) {
        guard wanted != pointerWatcher.isWatching else { return }
        guard wanted else {
            pointerWatcher.stop()
            hiding?.cancel()
            hiding = nil
            isRevealed = true
            return
        }
        pointerWatcher.start()
    }

    /// Slides in at once. Slides out late, so a pointer crossing the gap does not chase the bar.
    private func updateReveal() {
        guard let window, let screen else { return }
        let settings = state.settings
        let point = NSEvent.mouseLocation
        let wanted = DockAutoHide.isRevealed(
            autoHides: settings.autoHides,
            wasRevealed: isRevealed,
            isOverDock: DockAutoHide.isOver(point, frame: window.frame),
            touchesEdge: DockAutoHide.touchesEdge(
                point,
                barFrame: frame(for: .rest, on: screen),
                position: settings.position,
                screen: screen.frame
            ),
            isHeld: pointerWatcher.isMenuOpen || requested == .folder || !state.launching.isEmpty
                || model.hasCard(from: window)
        )
        if wanted {
            hiding?.cancel()
            hiding = nil
            if !isRevealed {
                isRevealed = true
                place(sliding: true)
            }
        } else if isRevealed, hiding == nil {
            hiding = Task { [weak self] in
                try? await Task.sleep(for: DockAutoHide.hideDelay)
                guard let self, !Task.isCancelled else { return }
                hiding = nil
                isRevealed = false
                place(sliding: true)
            }
        }
    }
}

/// Saves the system Dock's auto-hide settings, hides it, and puts everything back.
enum SystemDock {
    private static let savedKey = "SystemDockSavedSettings"
    private static let keys = ["autohide", "autohide-delay"]
    private static var dock: CFString {
        "com.apple.dock" as CFString
    }

    static func hide() {
        guard UserDefaults.standard.dictionary(forKey: savedKey) == nil else { return }
        // A key the owner never set stays out of the saved values, so restoring removes it again.
        var saved: [String: Any] = [:]
        for key in keys {
            saved[key] = CFPreferencesCopyAppValue(key as CFString, dock)
        }
        UserDefaults.standard.set(saved, forKey: savedKey)
        write("autohide", true as CFBoolean)
        write("autohide-delay", 1000.0 as CFNumber)
        relaunch()
    }

    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedKey) else { return }
        for key in keys {
            write(key, saved[key] as CFPropertyList?)
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
        relaunch()
    }

    private static func write(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetAppValue(key as CFString, value, dock)
        CFPreferencesAppSynchronize(dock)
    }

    /// The Dock reads these settings only at launch.
    ///
    /// Restarted through launchd: a Dock that quits cleanly counts as a successful exit and stays down.
    private static func relaunch() {
        let launchctl = Process()
        launchctl.executableURL = URL(filePath: "/bin/launchctl")
        launchctl.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.Dock.agent"]
        try? launchctl.run()
    }
}
