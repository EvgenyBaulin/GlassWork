import CoreGraphics

/// Where the last tiled window ended up. Apps may round a size, as Terminal does to whole characters, so this
/// is the frame read back after the move and not the one that was asked for.
public struct TileMemory: Equatable, Sendable {
    public let app: Int32
    public let tile: TileTarget
    public let frame: CGRect

    public init(app: Int32, tile: TileTarget, frame: CGRect) {
        self.app = app
        self.tile = tile
        self.frame = frame
    }
}

/// Where a command sends a window. `tile` is empty for a free window moved to another display.
public struct TilePlan: Equatable, Sendable {
    public let frame: CGRect
    public let display: TileDisplay
    public let tile: TileTarget?
}

/// Decides where a window goes. It only does arithmetic, so every case is testable without moving a window.
///
/// All frames use the system's coordinates. See `ScreenSpace` for the way to and from Accessibility.
public struct TilePlanner: Sendable {
    /// Enough for rounding, and too little to mistake a window someone moved by hand.
    private static let tolerance = 2.0

    /// Primary display first, as macOS lists them.
    public let displays: [TileDisplay]

    public init(displays: [TileDisplay]) {
        self.displays = displays
    }

    public func plan(_ command: TileCommand, window: CGRect, app: Int32, memory: TileMemory?) -> TilePlan? {
        guard let display = display(of: window) else { return nil }
        let current = tile(of: window, on: display, app: app, memory: memory)
        switch command {
        case let .place(layout):
            let step = current?.layout == layout ? (current?.step ?? 0) + 1 : 0
            let tile = TileTarget(layout, step: step % layout.stepCount)
            return TilePlan(frame: tile.frame(in: display.visibleFrame), display: display, tile: tile)
        case .previousDisplay:
            return plan(window, tile: current, from: display, offset: -1)
        case .nextDisplay:
            return plan(window, tile: current, from: display, offset: 1)
        }
    }

    /// The display with the largest part of the window. A window on none of them counts as on the primary.
    public func display(of window: CGRect) -> TileDisplay? {
        let best = displays.max { area(of: window, on: $0) < area(of: window, on: $1) }
        return best.flatMap { area(of: window, on: $0) > 0 ? $0 : nil } ?? displays.first
    }

    /// A window can refuse a size. This keeps what it took on the screen, with the title bar always reachable.
    public static func settled(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let left = frame.width > visible.width
            ? visible.minX
            : min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        let top = frame.height > visible.height
            ? visible.maxY
            : max(min(frame.maxY, visible.maxY), visible.minY + frame.height)
        return CGRect(x: left, y: top - frame.height, width: frame.width, height: frame.height)
    }

    private func area(of window: CGRect, on display: TileDisplay) -> Double {
        let shared = window.intersection(display.frame)
        return shared.isNull ? 0 : shared.width * shared.height
    }

    /// Displays from left to right, and from top to bottom where they stand above each other.
    private var ordered: [TileDisplay] {
        displays.sorted { first, second in
            first.frame.minX == second.frame.minX
                ? first.frame.maxY > second.frame.maxY
                : first.frame.minX < second.frame.minX
        }
    }

    private func tile(of window: CGRect, on display: TileDisplay, app: Int32, memory: TileMemory?) -> TileTarget? {
        if let memory, memory.app == app, Self.isClose(memory.frame, window) {
            return memory.tile
        }
        return TileTarget.all.first { Self.isClose($0.frame(in: display.visibleFrame), window) }
    }

    private func plan(_ window: CGRect, tile: TileTarget?, from source: TileDisplay, offset: Int) -> TilePlan? {
        let list = ordered
        guard list.count > 1, let index = list.firstIndex(of: source) else { return nil }
        let target = list[(index + offset + list.count) % list.count]
        guard let tile else {
            return TilePlan(frame: Self.carried(window, from: source, to: target), display: target, tile: nil)
        }
        return TilePlan(frame: tile.frame(in: target.visibleFrame), display: target, tile: tile)
    }

    /// A free window keeps its size where it fits, and its middle stays at the same share of the screen.
    private static func carried(_ window: CGRect, from source: TileDisplay, to target: TileDisplay) -> CGRect {
        let old = source.visibleFrame
        let new = target.visibleFrame
        let width = min(window.width, new.width)
        let height = min(window.height, new.height)
        let middleX = new.minX + (window.midX - old.minX) / old.width * new.width
        let middleY = new.minY + (window.midY - old.minY) / old.height * new.height
        let frame = CGRect(
            x: (middleX - width / 2).rounded(),
            y: (middleY - height / 2).rounded(),
            width: width,
            height: height
        )
        return settled(frame, in: new)
    }

    private static func isClose(_ first: CGRect, _ second: CGRect) -> Bool {
        abs(first.minX - second.minX) <= tolerance && abs(first.minY - second.minY) <= tolerance
            && abs(first.width - second.width) <= tolerance && abs(first.height - second.height) <= tolerance
    }
}
