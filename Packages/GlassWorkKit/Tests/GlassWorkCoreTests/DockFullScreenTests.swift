import CoreGraphics
@testable import GlassWorkCore
import Testing

struct DockFullScreenTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func aFrontWindowFillingTheScreenCovers() {
        let windows = [DockFullScreen.Window(pid: 7, layer: 0, bounds: screen)]

        #expect(DockFullScreen.covers(windows, screen: screen, frontPID: 7))
    }

    @Test func aZoomedWindowLeavesTheMenuBarAndDoesNotCover() {
        let zoomed = CGRect(x: 0, y: 33, width: 1512, height: 949)

        #expect(!DockFullScreen.covers([.init(pid: 7, layer: 0, bounds: zoomed)], screen: screen, frontPID: 7))
    }

    @Test func onlyTheFrontAppsNormalWindowsCount() {
        let windows = [
            DockFullScreen.Window(pid: 8, layer: 0, bounds: screen),
            DockFullScreen.Window(pid: 7, layer: 25, bounds: screen),
        ]

        #expect(!DockFullScreen.covers(windows, screen: screen, frontPID: 7))
    }

    @Test func anotherScreenDoesNotCount() {
        let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)

        #expect(!DockFullScreen.covers([.init(pid: 7, layer: 0, bounds: other)], screen: screen, frontPID: 7))
    }
}
