import CoreGraphics
import Foundation

/// Whether the front app fills the Dock's screen, as an app in full screen does. Pure: the window list comes in.
public enum DockFullScreen {
    /// One on-screen window, in the window server's top-left coordinates.
    public struct Window: Sendable, Equatable {
        public let pid: Int32
        public let layer: Int
        public let bounds: CGRect

        public init(pid: Int32, layer: Int, bounds: CGRect) {
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
        }
    }

    /// A normal window of the front app that covers the whole screen, menu bar included. A zoomed window leaves the
    /// menu bar out, so it does not count.
    public static func covers(_ windows: [Window], screen: CGRect, frontPID: Int32) -> Bool {
        windows.contains { window in
            window.pid == frontPID && window.layer == 0
                && abs(window.bounds.minX - screen.minX) < 1 && abs(window.bounds.minY - screen.minY) < 1
                && abs(window.bounds.width - screen.width) < 1 && abs(window.bounds.height - screen.height) < 1
        }
    }
}
