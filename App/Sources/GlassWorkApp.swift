import GlassWorkCore
import SwiftUI

@main
struct GlassWorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Windows are created on demand; the app lives in the menu bar.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    /// A click on a widget can be what launches the app, and then it arrives before the model exists.
    private var pendingModule: ModuleID?

    func applicationDidFinishLaunching(_: Notification) {
        model = AppModel()
        if let pendingModule {
            model?.showPanelAtPointer(pendingModule)
        }
        pendingModule = nil
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let module = urls.compactMap(WidgetLink.module).last else { return }
        if let model {
            model.showPanelAtPointer(module)
        } else {
            pendingModule = module
        }
    }

    func applicationWillTerminate(_: Notification) {
        model?.prepareToQuit()
    }

    /// Opening the app again from Finder or Spotlight shows Settings.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        model?.showSettings()
        return false
    }
}
