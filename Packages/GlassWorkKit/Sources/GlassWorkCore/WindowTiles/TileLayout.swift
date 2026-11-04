import CoreGraphics

/// A part of the screen as shares of its width and height, measured from the top left as people see it.
public struct TileRegion: Equatable, Sendable {
    public let left: Double
    public let right: Double
    public let top: Double
    public let bottom: Double

    public init(left: Double, right: Double, top: Double, bottom: Double) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    /// The region in `visible`, which uses the system's coordinates: y grows upward, so the top share counts
    /// down from `maxY`. Inner edges land on whole points, and neighbours round the same share the same way,
    /// so tiles side by side share an edge with no gap and no overlap.
    public func frame(in visible: CGRect) -> CGRect {
        let minX = Self.edge(left, from: visible.minX, length: visible.width)
        let maxX = Self.edge(right, from: visible.minX, length: visible.width)
        let maxY = Self.edge(top, from: visible.maxY, length: -visible.height)
        let minY = Self.edge(bottom, from: visible.maxY, length: -visible.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func edge(_ share: Double, from start: Double, length: Double) -> Double {
        let position = start + length * share
        return share == 0 || share == 1 ? position : position.rounded()
    }
}

/// The twelve places a window can be sent to. "Full screen" fills the screen without entering a macOS Space.
public enum TileLayout: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case fullScreen, center, firstThird, lastThird
    case topLeft, topRight, bottomLeft, bottomRight

    /// What a half takes on each press: half, two thirds, one third, then half again.
    private static let halfCycle = [1.0 / 2, 2.0 / 3, 1.0 / 3]

    /// How many places the layout goes through when its shortcut is pressed again.
    public var stepCount: Int {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: Self.halfCycle.count
        default: 1
        }
    }

    public func region(step: Int = 0) -> TileRegion {
        let share = Self.halfCycle[step % Self.halfCycle.count]
        return switch self {
        case .leftHalf: TileRegion(left: 0, right: share, top: 0, bottom: 1)
        case .rightHalf: TileRegion(left: 1 - share, right: 1, top: 0, bottom: 1)
        case .topHalf: TileRegion(left: 0, right: 1, top: 0, bottom: share)
        case .bottomHalf: TileRegion(left: 0, right: 1, top: 1 - share, bottom: 1)
        case .fullScreen: TileRegion(left: 0, right: 1, top: 0, bottom: 1)
        case .center: TileRegion(left: 0.2, right: 0.8, top: 0.15, bottom: 0.85)
        case .firstThird: TileRegion(left: 0, right: 1.0 / 3, top: 0, bottom: 1)
        case .lastThird: TileRegion(left: 2.0 / 3, right: 1, top: 0, bottom: 1)
        case .topLeft: TileRegion(left: 0, right: 0.5, top: 0, bottom: 0.5)
        case .topRight: TileRegion(left: 0.5, right: 1, top: 0, bottom: 0.5)
        case .bottomLeft: TileRegion(left: 0, right: 0.5, top: 0.5, bottom: 1)
        case .bottomRight: TileRegion(left: 0.5, right: 1, top: 0.5, bottom: 1)
        }
    }
}

/// One exact place: a layout and how far through its presses it is.
public struct TileTarget: Hashable, Sendable {
    public let layout: TileLayout
    public let step: Int

    public init(_ layout: TileLayout, step: Int = 0) {
        self.layout = layout
        self.step = step
    }

    public static var all: [TileTarget] {
        TileLayout.allCases.flatMap { layout in
            (0 ..< layout.stepCount).map { TileTarget(layout, step: $0) }
        }
    }

    public var region: TileRegion {
        layout.region(step: step)
    }

    public func frame(in visible: CGRect) -> CGRect {
        region.frame(in: visible)
    }
}
