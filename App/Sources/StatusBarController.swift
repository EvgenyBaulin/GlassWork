import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The GlassWork icon, the hiding separator and one status item per module.
@MainActor
final class StatusBarController: NSObject {
    private unowned let model: AppModel
    private let hub = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let separator = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var items: [ModuleID: ModuleItem] = [:]
    private var collapsed = false
    private var hideTask: Task<Void, Never>?
    private var hiding = HidingSettings()

    private static let separatorLength: CGFloat = 16
    /// Wider than any screen, so everything left of the separator moves off-screen.
    private static let collapsedLength: CGFloat = 10000

    var hubButton: NSStatusBarButton? {
        hub.button
    }

    init(model: AppModel) {
        self.model = model
        super.init()
        hub.autosaveName = "GlassWorkHub"
        separator.autosaveName = "GlassWorkSeparator"
        configureHub()
        configureSeparator()
    }

    func apply(_ settings: AppSettings) {
        hiding = settings.hiding
        separator.isVisible = settings.hiding.isEnabled
        if !settings.hiding.isEnabled, collapsed {
            setCollapsed(false)
        }

        let wanted = settings.modules.filter { $0.id.isAvailable && $0.mode == .menuBar }
        for id in items.keys where !wanted.contains(where: { $0.id == id }) {
            items.removeValue(forKey: id)?.remove()
        }
        // Position is measured from the right edge, so the last module in settings goes closest to it.
        for (index, setting) in wanted.reversed().enumerated() {
            Self.suggestPosition(for: setting.id, slot: index)
            if let item = items[setting.id] {
                item.update(style: setting.style, numbers: settings.numberStyle, options: setting.options)
            } else {
                items[setting.id] = ModuleItem(setting: setting, numbers: settings.numberStyle, model: model)
            }
        }
    }

    func refreshItems() {
        items.values.forEach { $0.refresh() }
    }

    func owns(_ window: NSWindow) -> Bool {
        window === hub.button?.window || window === separator.button?.window
            || items.values.contains { $0.window === window }
    }

    /// Seeds macOS's saved position for a new item. ⌘-dragged items keep the place the user gave them.
    private static func suggestPosition(for module: ModuleID, slot: Int) {
        let key = "NSStatusItem Preferred Position GlassWork-\(module.rawValue)"
        guard UserDefaults.standard.object(forKey: key) == nil else { return }
        UserDefaults.standard.set(firstSlot + CGFloat(slot) * slotWidth, forKey: key)
    }

    private static let firstSlot: CGFloat = 400
    private static let slotWidth: CGFloat = 2

    /// Shows hidden items and hides them again after the configured delay.
    func revealHidden() {
        guard hiding.isEnabled, collapsed else { return }
        setCollapsed(false)
        scheduleHide()
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
        separator.length = Self.separatorLength
        updateSeparatorImage()
    }

    @objc private func hubClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            model.toggleHub()
        }
    }

    @objc private func separatorClicked() {
        model.closePanels()
        setCollapsed(!collapsed)
        if !collapsed {
            scheduleHide()
        }
    }

    private func setCollapsed(_ value: Bool) {
        collapsed = value
        separator.length = value ? Self.collapsedLength : Self.separatorLength
        updateSeparatorImage()
    }

    private func updateSeparatorImage() {
        let name = collapsed ? "chevron.left" : "chevron.right"
        separator.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let delay = hiding.autoHideSeconds
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.setCollapsed(true)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: loc("Settings…"), action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: loc("Quit GlassWork"), action: #selector(quit), keyEquivalent: "q").target = self
        hub.menu = menu
        hub.button?.performClick(nil)
        hub.menu = nil
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

    var window: NSWindow? {
        item.button?.window
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
        render()
        observeRemoval()
    }

    func update(style: DisplayStyle, numbers: NumberStyle, options: [String: String]) {
        // A setting can change what the longest text is, such as which pair Rates shows.
        let newWidth = MenuBarItemView.width(module: module, style: style, numbers: numbers, monitor: model.monitor)
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
        renderer.appearance = item.button?.effectiveAppearance
        let size = CGSize(width: width, height: NSStatusBar.system.thickness)
        if let image = renderer.image(size: size) {
            item.button?.image = image
        }
    }

    private func render() {
        width = MenuBarItemView.width(
            module: module,
            style: style,
            numbers: numbers,
            options: options,
            monitor: model.monitor
        )
        item.length = width
        renderer.style = style
        renderer.numbers = numbers
        renderer.appearance = item.button?.effectiveAppearance
        renderer.options = options
        let size = CGSize(width: width, height: NSStatusBar.system.thickness)
        item.button?.image = renderer.image(size: size, force: true)
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
        if module.isClickAction {
            model.performClickAction(module)
            refresh()
        } else {
            model.togglePanel(module, from: button)
        }
    }
}
