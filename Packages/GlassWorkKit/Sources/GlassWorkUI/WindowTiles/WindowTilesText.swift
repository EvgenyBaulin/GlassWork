import GlassWorkCore

public extension TileLayout {
    var title: String {
        switch self {
        case .leftHalf: loc("Left half")
        case .rightHalf: loc("Right half")
        case .topHalf: loc("Top half")
        case .bottomHalf: loc("Bottom half")
        case .fullScreen: loc("Full screen")
        case .center: loc("Center")
        case .firstThird: loc("First third")
        case .lastThird: loc("Last third")
        case .topLeft: loc("Top left")
        case .topRight: loc("Top right")
        case .bottomLeft: loc("Bottom left")
        case .bottomRight: loc("Bottom right")
        }
    }
}

public extension TileTarget {
    /// A half pressed again no longer is one, so the label says what it became.
    var title: String {
        switch (layout, step) {
        case (.leftHalf, 1): loc("Left two thirds")
        case (.leftHalf, 2): loc("Left third")
        case (.rightHalf, 1): loc("Right two thirds")
        case (.rightHalf, 2): loc("Right third")
        case (.topHalf, 1): loc("Top two thirds")
        case (.topHalf, 2): loc("Top third")
        case (.bottomHalf, 1): loc("Bottom two thirds")
        case (.bottomHalf, 2): loc("Bottom third")
        default: layout.title
        }
    }
}

public extension TileCommand {
    var title: String {
        switch self {
        case let .place(layout): layout.title
        case .previousDisplay: loc("Previous display")
        case .nextDisplay: loc("Next display")
        }
    }

    /// The label for the preview, which knows how far through its presses a half has got.
    func title(for plan: TilePlan) -> String {
        switch self {
        case .place: plan.tile?.title ?? title
        case .previousDisplay, .nextDisplay: title
        }
    }
}

/// Why a shortcut moved nothing.
public enum WindowTilesNotice: Equatable, Sendable {
    case needsAccessibility
    case noWindow
    case cannotMove
    case fullScreen
    case oneDisplay

    /// Instructions need time to be read.
    public var duration: Duration {
        self == .needsAccessibility ? .seconds(7) : .seconds(2)
    }

    var symbol: String {
        switch self {
        case .needsAccessibility: "lock.shield"
        case .noWindow, .cannotMove: "macwindow"
        case .fullScreen: "arrow.up.left.and.arrow.down.right"
        case .oneDisplay: "display"
        }
    }

    var title: String {
        switch self {
        case .needsAccessibility: loc("GlassWork needs Accessibility")
        case .noWindow: loc("No window to move")
        case .cannotMove: loc("This window can't be moved")
        case .fullScreen: loc("Leave full screen first")
        case .oneDisplay: loc("There is only one display")
        }
    }

    var detail: String? {
        guard self == .needsAccessibility else { return nil }
        return loc("""
        Add GlassWork in System Settings → Privacy & Security → Accessibility, then press the shortcut again.
        """)
    }
}
