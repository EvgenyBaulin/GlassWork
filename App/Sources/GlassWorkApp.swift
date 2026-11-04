import Carbon
import GlassWorkCore
import GlassWorkUI
import SwiftUI

@main
struct GlassWorkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Windows are created on demand. The scene is here for its menus: left alone, ⌘, would open it empty.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(loc("Settings…")) { delegate.showSettings() }.keyboardShortcut(",")
                }
                CommandGroup(replacing: .saveItem) {
                    Button(loc("Close Window")) { NSApp.keyWindow?.performClose(nil) }.keyboardShortcut("w")
                }
                CommandGroup(after: .windowArrangement) {
                    Button("GlassWork") { delegate.showMainWindow() }.keyboardShortcut("0")
                }
                CommandGroup(replacing: .help) {}
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    /// A click on a widget can be what launches the app, and then it arrives before the model exists.
    private var pendingModule: ModuleID?

    func applicationDidFinishLaunching(_: Notification) {
        // Read first: the event is only there during launch.
        let isQuietLaunch = wasOpenedAtLogin
        model = AppModel()
        if let pendingModule {
            model?.showPanelAtPointer(pendingModule)
        } else if !isQuietLaunch {
            model?.showMainWindowAtLaunch()
        }
        pendingModule = nil
    }

    /// Logging in should bring back the menu bar, not put a window in front of everything.
    private var wasOpenedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
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

    /// The app lives in the menu bar, so closing the window is not the end of it.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// A click on the Dock icon, or opening the app again from Finder or Spotlight.
    ///
    /// The flag says nothing here: the Dock bar and desktop widgets are windows too.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func showMainWindow() {
        model?.showMainWindow()
    }

    func showSettings() {
        model?.showSettings()
    }
}
