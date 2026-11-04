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
}

/// Accessibility puts the origin at the top left of the primary display, with y growing downward.
public enum ScreenSpace {
    /// Converts a rectangle between the two systems, in either direction. `primaryHeight` is the height of the
    /// display with the menu bar in macOS's arrangement, whichever display the rectangle is on.
    public static func flipped(_ rect: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
