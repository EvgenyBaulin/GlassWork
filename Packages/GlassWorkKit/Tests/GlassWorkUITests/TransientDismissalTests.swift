import AppKit
@testable import GlassWorkUI
import Testing

/// The rules only: nothing here is shown on screen.
@MainActor
struct TransientDismissalTests {
    private let panel = NSPanel()
    private let statusItem = NSWindow()
    private let settings = NSWindow()

    private func dismissal() -> TransientDismissal {
        let statusItem = statusItem
        return TransientDismissal(panel: panel, isStatusItem: { $0 === statusItem }, ownProcess: 100) {}
    }

    @Test func clickInsideThePanelKeepsIt() {
        #expect(!dismissal().shouldDismiss(clickIn: panel, type: .leftMouseDown))
    }

    @Test func clickOnAnotherOwnWindowClosesIt() {
        #expect(dismissal().shouldDismiss(clickIn: settings, type: .leftMouseDown))
        #expect(dismissal().shouldDismiss(clickIn: settings, type: .rightMouseDown))
    }

    @Test func leftClickOnAStatusItemIsLeftToItsAction() {
        #expect(!dismissal().shouldDismiss(clickIn: statusItem, type: .leftMouseDown))
    }

    @Test func rightClickOnAStatusItemClosesIt() {
        #expect(dismissal().shouldDismiss(clickIn: statusItem, type: .rightMouseDown))
    }

    @Test func anEventWithoutAWindowChangesNothing() {
        #expect(!dismissal().shouldDismiss(clickIn: nil, type: .leftMouseDown))
    }

    @Test func aFolderChooserKeepsThePanel() {
        #expect(!dismissal().shouldDismiss(clickIn: NSOpenPanel(), type: .leftMouseDown))
    }

    @Test func escapeClosesOnlyThePanelItWasPressedIn() {
        #expect(dismissal().shouldDismiss(keyCode: 53, in: panel))
        #expect(!dismissal().shouldDismiss(keyCode: 53, in: settings))
        #expect(!dismissal().shouldDismiss(keyCode: 0, in: panel))
    }

    @Test func anotherAppInFrontClosesIt() {
        #expect(dismissal().shouldDismiss(activated: 200))
        #expect(!dismissal().shouldDismiss(activated: 100))
    }

    /// The closing happens through the real notification path.
    @Test func spaceChangeClosesIt() {
        var closed = 0
        let dismissal = TransientDismissal(panel: panel) { closed += 1 }
        dismissal.start()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        dismissal.stop()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )
        #expect(closed == 1)
    }
}
