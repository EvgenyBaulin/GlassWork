import CoreGraphics

/// A screen, in the system's coordinates: origin at the bottom left of the primary display, y grows upward.
public struct TileDisplay: Equatable, Sendable {
    public let frame: CGRect
    /// The part left after the menu bar and the Dock.
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    /// The same display with the strip below `height`, measured from the screen's bottom edge, taken away.
    /// For GlassWork's own Dock: the system hides its Dock meanwhile, so `visibleFrame` leaves no room.
    public func reservingBottom(_ height: Double) -> TileDisplay {
        let bottom = max(visibleFrame.minY, frame.minY + height)
        return TileDisplay(
            frame: frame,
            visibleFrame: CGRect(
                x: visibleFrame.minX,
                y: bottom,
                width: visibleFrame.width,
                height: max(visibleFrame.maxY - bottom, 0)
            )
        )
    }

    /// The same display with a strip `depth` deep along the Dock's edge taken away.
    public func reserving(_ depth: Double, at position: DockPosition) -> TileDisplay {
        var visible = visibleFrame
        switch position {
        case .bottom:
            return reservingBottom(depth)
        case .left:
            let left = max(visible.minX, frame.minX + depth)
            visible.size.width = max(visible.maxX - left, 0)
            visible.origin.x = left
        case .right:
            visible.size.width = max(min(visible.maxX, frame.maxX - depth) - visible.minX, 0)
        }
        return TileDisplay(frame: frame, visibleFrame: visible)
    }
}

/// Accessibility puts the origin at the top left of the primary display, with y growing downward.
public enum ScreenSpace {
    /// Converts a rectangle between the two systems, in either direction. `primaryHeight` is the height of the
    /// display with the menu bar in macOS's arrangement, whichever display the rectangle is on.
    public static func flipped(_ rect: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
