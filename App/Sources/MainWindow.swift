import AppKit
import GlassWorkCore
import GlassWorkUI
import SwiftUI

/// The regular window behind the Dock icon. Closing it leaves the app running in the menu bar.
@MainActor
final class MainWindowController {
    private unowned let model: AppModel
    private let navigation = MainNavigation()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        navigation.onChange = { [weak self] in self?.reportVisibleSection() }
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let view = MainWindowView(navigation: navigation, openSettings: { [weak self] in self?.model.showSettings() }) {
            MainWindowContent(route: $0, model: self.model, navigation: self.navigation)
        }
        .environment(\.panelActions, model.actions)
        .environment(\.fanControl, model.fans)
        let created = NSWindow(contentViewController: NSHostingController(rootView: view))
        created.title = "GlassWork"
        created.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        created.toolbarStyle = .unified
        created.contentMinSize = CGSize(width: 760, height: 540)
        created.setContentSize(CGSize(width: 900, height: 640))
        created.center()
        created.setFrameAutosaveName("GlassWorkMain")
        created.isReleasedWhenClosed = false
        observe(created)
        return created
    }

    /// Hidden behind other windows, minimized or closed all count as not showing.
    private func observe(_ window: NSWindow) {
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
                let isClosing = note.name == NSWindow.willCloseNotification
                MainActor.assumeIsolated { self?.reportVisibleSection(isClosing: isClosing) }
            }
        }
    }

    private func reportVisibleSection(isClosing: Bool = false) {
        let isVisible = !isClosing && window?.occlusionState.contains(.visible) == true
        model.mainWindowChanged(visibleSection: isVisible ? navigation.route.section : nil)
    }
}

/// What each section shows. A new section needs only a line here.
private struct MainWindowContent: View {
    let route: MainRoute
    let model: AppModel
    let navigation: MainNavigation

    var body: some View {
        switch route.section {
        case .apps: apps
        case .clipboard:
            ScrollView {
                ModulePanel(module: .clipboard, monitor: model.monitor).frame(maxWidth: .infinity)
            }
        case .widgets: WidgetsPane(store: model.store)
        case .dock: DockPane(store: model.store)
        case .unlock:
            SectionPlaceholder(.unlock, heading: loc("Unlock this Mac"))
        case .overview, .windowTiles, .settings:
            SectionPlaceholder(route.section)
        }
    }

    @ViewBuilder
    private var apps: some View {
        if let item = route.item {
            AppDetail(id: item.id, name: item.title, monitor: model.monitor).id(item.id)
        } else {
            AppsSection(monitor: model.monitor) { app in
                navigation.go(to: MainRoute(section: .apps, item: .init(id: app.id, title: app.name)))
            }
        }
    }
}
