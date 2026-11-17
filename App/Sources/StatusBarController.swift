import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The GlassWork icon, the hiding separator and one status item per module.
@MainActor
final class StatusBarController: NSObject {
    private unowned let model: AppModel
    private let hub = makeItem(hubName, length: NSStatusItem.squareLength, position: hubPosition)
    private let separator = makeItem(separatorName, length: NSStatusItem.variableLength, position: separatorPosition)
    private var items: [ModuleID: ModuleItem] = [:]
    private var barOrder: [ModuleID] = []
    /// Left of `separator`: what is dragged left of it stays hidden when the bar opens.
    private let alwaysHiddenSeparator = makeItem(
        alwaysHiddenName,
        length: NSStatusItem.variableLength,
        position: alwaysHiddenPosition
    )
    private let hidden = HiddenBarDriver()
    private var hiding = HidingSettings()
    private var appliedLayout: HiddenBarLayout?
    private lazy var seconds = SecondTicker { [weak self] modules in
        for module in modules {
            self?.items[module]?.refresh()
        }
    }

    private static let separatorLength: CGFloat = 16
    /// Wider than any screen, so everything left of the separator moves off-screen.
    private static let collapsedLength: CGFloat = 10000
    private static let hubName = "GlassWorkHub"
    private static let separatorName = "GlassWorkSeparator"
    private static let alwaysHiddenName = "GlassWorkAlwaysHiddenSeparator"
    /// Positions count from the right edge and macOS keeps its own items at about 170 and up, in the same
    /// units. Starting at the very right puts those items left of the separator, so hiding covers them
    /// without moving anything of theirs. The clock and Control Center stay to the right of everything.
    private static let hubPosition: CGFloat = 0
    private static let separatorPosition: CGFloat = 1
    /// Far to the left, so nothing starts out left of it: macOS items and modules stay in the hidden section
    /// until the user ⌘-drags them across.
    private static let alwaysHiddenPosition: CGFloat = 800

    var hubButton: NSStatusBarButton? {
        hub.button
    }

    /// The menu bar button of a module, nil when it is not in the menu bar.
    func button(for module: ModuleID) -> NSStatusBarButton? {
        items[module]?.button
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        configureHub()
        configureSeparator()
        configureAlwaysHiddenSeparator()
        hidden.placement = { [weak self] in self?.separatorPlacement() }
        hidden.onChange = { [weak self] machine in self?.applyLayout(machine) }
    }

    func apply(_ settings: AppSettings) {
        let turnedOn = settings.hiding.isEnabled && !hiding.isEnabled
        let alwaysHiddenOn = settings.hiding.isEnabled && settings.hiding.hasAlwaysHidden
        let alwaysHiddenTurnedOn = alwaysHiddenOn && !(hiding.isEnabled && hiding.hasAlwaysHidden)
        hiding = settings.hiding
        if turnedOn {
            // macOS forgets the position of an item that was not visible.
            Self.seedPosition(Self.separatorName, Self.separatorPosition)
        }
        if alwaysHiddenTurnedOn {
            Self.seedPosition(Self.alwaysHiddenName, Self.alwaysHiddenPosition)
        }
        separator.isVisible = settings.hiding.isEnabled
        alwaysHiddenSeparator.isVisible = alwaysHiddenOn
        hidden.configure(settings.hiding)
        model.shortcuts.setActive(.hiddenBar, settings.hiding.isEnabled)

        let wanted = settings.modules.filter { $0.id.isAvailable && $0.mode == .menuBar }
        for id in items.keys where !wanted.contains(where: { $0.id == id }) {
            items.removeValue(forKey: id)?.remove()
        }
        let order = wanted.map(\.id)
        let isReordered = AppSettings.isReordered(from: barOrder, to: order)
        barOrder = order
        if isReordered {
            // macOS reads a saved position only when an item is created.
            items.values.forEach { $0.remove() }
            items = [:]
        }
        // Position is measured from the right edge, so the last module in settings goes closest to it.
        for (index, setting) in wanted.reversed().enumerated() {
            if isReordered {
                Self.setPosition(for: setting.id, slot: index)
            } else {
                Self.suggestPosition(for: setting.id, slot: index)
            }
            if let item = items[setting.id] {
                item.update(style: setting.style, numbers: settings.numberStyle, options: setting.options)
            } else {
                items[setting.id] = ModuleItem(setting: setting, numbers: settings.numberStyle, model: model)
            }
        }
        seconds.follow(Set(wanted.map(\.id)))
    }

    func refreshItems() {
        items.values.forEach { $0.refresh() }
    }

    /// Only our visible status items on the island's display can constrain its right wing.
    func leftmostItemX(on screen: NSScreen) -> CGFloat? {
        let windows = [hub.button?.window, separator.button?.window, alwaysHiddenSeparator.button?.window] + items
            .values.map(\.window)
        return windows.compactMap { window -> CGFloat? in
            guard let window, window.isVisible, window.screen == screen,
                  window.frame.minX >= screen.frame.midX, window.frame.width < screen.frame.width else { return nil }
            return window.frame.minX
        }.min()
    }

    func owns(_ window: NSWindow) -> Bool {
        window === hub.button?.window || window === separator.button?.window
            || window === alwaysHiddenSeparator.button?.window
            || items.values.contains { $0.window === window }
    }

    private static func makeItem(_ name: String, length: CGFloat, position: CGFloat) -> NSStatusItem {
        seedPosition(name, position)
        let item = NSStatusBar.system.statusItem(withLength: length)
        item.autosaveName = name
        return item
    }

    /// Seeds macOS's saved position for a new item. ⌘-dragged items keep the place the user gave them.
    private static func seedPosition(_ name: String, _ position: CGFloat) {
        let key = "NSStatusItem Preferred Position \(name)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(position, forKey: key)
    }

    private static func suggestPosition(for module: ModuleID, slot: Int) {
        seedPosition("GlassWork-\(module.rawValue)", firstSlot + CGFloat(slot) * slotWidth)
    }

    /// A new order from Settings wins over where the item was ⌘-dragged to.
    private static func setPosition(for module: ModuleID, slot: Int) {
        let key = "NSStatusItem Preferred Position GlassWork-\(module.rawValue)"
        UserDefaults.standard.set(firstSlot + CGFloat(slot) * slotWidth, forKey: key)
    }

    private static let firstSlot: CGFloat = 400
    private static let slotWidth: CGFloat = 2

    /// Shows hidden items and hides them again after the configured delay.
    func revealHidden() {
        hidden.revealIfCollapsed()
    }

    /// The shortcut. Option held, which the shortcut itself does not use, also opens the always-hidden section.
    func toggleHidden(option: Bool) {
        model.closePanels()
        hidden.toggle(option: option)
    }

    private func configureHub() {
        guard let button = hub.button else { return }
        button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "GlassWork")
        button.target = self
        button.action = #selector(hubClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparator() {
        guard let button = separator.button else { return }
        button.target = self
        button.action = #selector(separatorClicked)
        button.toolTip = loc("Click to show or hide. Hold ⌘ and drag an item across ‹ to choose.")
        separator.length = Self.separatorLength
        button.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    }

    @objc private func hubClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            model.toggleHub()
        }
    }

    private func configureAlwaysHiddenSeparator() {
        guard let button = alwaysHiddenSeparator.button else { return }
        button.toolTip = loc("Items dragged left of this mark stay hidden. Option-click ‹ to show them.")
        alwaysHiddenSeparator.length = Self.separatorLength
        button.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: nil)
        alwaysHiddenSeparator.isVisible = false
    }

    @objc private func separatorClicked() {
        model.closePanels()
        hidden.toggle(option: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
    }

    private func applyLayout(_ machine: HiddenBarMachine) {
        let layout = machine.layout
        guard layout != appliedLayout else { return }
        appliedLayout = layout
        separator.length = Self.length(layout.separator)
        if let alwaysHidden = layout.alwaysHidden {
            alwaysHiddenSeparator.length = Self.length(alwaysHidden)
        }
        let name = machine.isCollapsed ? "chevron.left" : "chevron.right"
        separator.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private static func length(_ length: HiddenBarSeparatorLength) -> CGFloat {
        length == .wide ? collapsedLength : separatorLength
    }

    private func separatorPlacement() -> HiddenBarDriver.Placement? {
        guard let window = separator.button?.window, let screen = window.screen ?? NSScreen.main else { return nil }
        let barHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        return HiddenBarDriver.Placement(
            separatorMaxX: window.frame.maxX,
            screenMaxY: screen.frame.maxY,
            barHeight: barHeight
        )
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: loc("Open GlassWork"), action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(withTitle: loc("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        addPauseItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: loc("About GlassWork"), action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: loc("Quit GlassWork"), action: #selector(quit), keyEquivalent: "q").target = self
        hub.menu = menu
        hub.button?.performClick(nil)
        hub.menu = nil
    }

    private func addPauseItems(to menu: NSMenu) {
        let pause = model.updatePause
        if pause.isPaused {
            let state = pause.pausedUntil.map { loc("Paused until \(Self.pauseEnd($0))") } ?? loc("Paused")
            let line = menu.addItem(withTitle: state, action: nil, keyEquivalent: "")
            line.isEnabled = false
            menu.addItem(withTitle: loc("Resume"), action: #selector(resumeUpdates), keyEquivalent: "").target = self
            return
        }
        let parent = menu.addItem(withTitle: loc("Pause updates"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (index, duration) in UpdatePause.allCases.enumerated() {
            let title = switch duration {
            case .fifteenMinutes: loc("15 minutes")
            case .oneHour: loc("1 hour")
            case .untilTomorrow: loc("Until tomorrow")
            case .indefinitely: loc("Indefinitely")
            }
            let item = submenu.addItem(withTitle: title, action: #selector(pauseUpdates(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
        }
        parent.submenu = submenu
    }

    /// The time alone for today, with the day added when the pause runs past midnight.
    private static func pauseEnd(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.timeText
        }
        return date.dateTimeText
    }

    @objc private func pauseUpdates(_ sender: NSMenuItem) {
        guard UpdatePause.allCases.indices.contains(sender.tag) else { return }
        model.updatePause.pause(UpdatePause.allCases[sender.tag])
    }

    @objc private func resumeUpdates() {
        model.updatePause.resume()
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openMainWindow() {
        model.showMainWindow()
    }

    @objc private func openSettings() {
        model.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// One module's status item with a live SwiftUI view inside.
@MainActor
final class ModuleItem: NSObject {
    private let module: ModuleID
    private unowned let model: AppModel
    private let item: NSStatusItem
    private var style: DisplayStyle
    private var numbers: NumberStyle
    private var options: [String: String]
    private let renderer: MenuBarItemRenderer
    private var width: CGFloat = 0
    private var visibility: NSKeyValueObservation?
    /// When the mouse went down on the Stopwatch item.
    private var pressedAt: Date?
    /// The help text is rebuilt now and then, not on every refresh: it only matters while the pointer rests here.
    private var tooltipBuiltAt = Date.distantPast

    var window: NSWindow? {
        item.button?.window
    }

    var button: NSStatusBarButton? {
        item.button
    }

    init(setting: ModuleSettings, numbers: NumberStyle, model: AppModel) {
        module = setting.id
        style = setting.style
        self.numbers = numbers
        options = setting.options
        self.model = model
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        renderer = MenuBarItemRenderer(
            module: setting.id,
            style: setting.style,
            numbers: numbers,
            options: setting.options,
            monitor: model.monitor
        )
        super.init()
        item.autosaveName = "GlassWork-\(setting.id.rawValue)"
        item.behavior = .removalAllowed
        item.button?.target = self
        item.button?.action = #selector(clicked)
        if module == .stopwatch {
            // A hold is told from a click by the time between the press and the release.
            item.button?.sendAction(on: [.leftMouseDown, .leftMouseUp])
        }
        render()
        observeRemoval()
    }

    func update(style: DisplayStyle, numbers: NumberStyle, options: [String: String]) {
        // A setting can change what the longest text is, such as which pair Rates shows.
        let newWidth = MenuBarItemView.width(
            module: module,
            style: style,
            numbers: numbers,
            options: options,
            monitor: model.monitor
        )
        let isSame = style == self.style && numbers == self.numbers && options == self.options
        guard !isSame || newWidth != width else { return }
        self.style = style
        self.numbers = numbers
        self.options = options
        render()
    }

    func remove() {
        visibility = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    func refresh() {
        // These follow their content: Now Playing changes with the track, the others can hide themselves.
        if module.canHideItself, width != currentWidth {
            render()
            return
        }
        renderer.appearance = item.button?.effectiveAppearance
        let size = CGSize(width: width, height: NSStatusBar.system.thickness)
        if let image = renderer.image(size: size) {
            item.button?.image = image
        }
        updateTooltip()
    }

    private func updateTooltip(force: Bool = false) {
        guard force || Date().timeIntervalSince(tooltipBuiltAt) >= 10 else { return }
        tooltipBuiltAt = Date()
        item.button?.toolTip = renderer.tooltip()
    }

    private var currentWidth: CGFloat {
        MenuBarItemView.width(module: module, style: style, numbers: numbers, options: options, monitor: model.monitor)
    }

    private func render() {
        width = currentWidth
        item.length = width
        renderer.style = style
        renderer.numbers = numbers
        renderer.appearance = item.button?.effectiveAppearance
        renderer.options = options
        let size = CGSize(width: width, height: NSStatusBar.system.thickness)
        item.button?.image = renderer.image(size: size, force: true)
        updateTooltip(force: true)
    }

    /// ⌘-dragging an item out keeps the module in the Hub.
    private func observeRemoval() {
        visibility = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in
                guard let self else { return }
                self.model.store.update { $0.update(self.module) { $0.mode = .hubOnly } }
            }
        }
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        if module == .stopwatch, let event = NSApp.currentEvent {
            switch event.type {
            case .leftMouseDown:
                pressedAt = Date()
            case .leftMouseUp:
                let outcome = PressHold.outcome(down: pressedAt, released: Date())
                pressedAt = nil
                if outcome == .hold {
                    model.resetStopwatch()
                } else {
                    model.performClickAction(module)
                }
                refresh()
            default:
                break
            }
            return
        }
        if module == .colours {
            // A click picks a colour; Option opens the panel with the colours picked before.
            if NSEvent.modifierFlags.contains(.option) {
                model.togglePanel(module, from: button)
            } else {
                model.pickColour()
            }
            return
        }
        if module.isClickAction {
            model.performClickAction(module)
            refresh()
        } else if module == .overview, options.choice(ItemOption.overviewClick, default: OverviewClick.panel) == .hub {
            model.toggleHub(from: button)
        } else {
            model.togglePanel(module, from: button)
        }
    }
}
