import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct DockLabelTests {
    @Test func anAppShowsItsName() {
        let app = DockApp(path: "/Applications/Notes.app", name: "Notes")
        #expect(DockLabelText.of(.app(app), stackTitle: "") == "Notes")
    }

    @Test func aFolderShowsItsNameAndAppCount() {
        let apps = (0 ..< 3).map { DockApp(path: "/Applications/A\($0).app", name: "A\($0)") }
        let label = DockLabelText.of(.folder(AppFolder(name: "Work", apps: apps)), stackTitle: "")
        #expect(label.hasPrefix("Work"))
        #expect(label.contains("3"))
    }

    @Test func aWidgetShowsItsQuickAction() {
        let label = DockLabelText.of(.widget(.timers), stackTitle: "")
        #expect(label.contains(ModuleID.timers.title))
        #expect(label.contains(ModuleID.timers.dockClickTitle))
    }

    @Test func aStackUsesItsTitle() {
        let stack = DockItem.stack(DockStack.downloads(name: "Downloads"))
        #expect(DockLabelText.of(stack, stackTitle: "Downloads · 40%") == "Downloads · 40%")
    }
}
