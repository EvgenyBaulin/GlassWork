import Foundation
import Observation

/// What the Dock window has to make room for.
public enum DockSpace: Int, Comparable, Sendable {
    /// Just the bar. Nothing around it can swallow a click meant for the window behind.
    case rest
    /// Icons growing out of the bar.
    case magnified
    /// A folder's card above the bar.
    case folder

    public static func < (lhs: DockSpace, rhs: DockSpace) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where the bar and its icons go for a pointer position. Pure, so the motion is testable.
///
/// Positions are measured along the bar, from the middle of the Dock, which never moves: across the screen for
/// a Dock at the bottom, down it for one at a side. The pointer has to be read in that same frame: read inside
/// the bar, it would shift as the bar widens and feed back into the sizes.
public struct DockBarLayout: Equatable, Sendable {
    public static let spacing = 8.0
    public static let padding = 8.0
    /// The gap and the running dot under an icon.
    public static let indicator = 7.0
    /// How high a launching icon jumps, as a share of its size.
    public static let bounce = 0.4
    public static let folderCardWidth = 430.0
    public static let folderCardHeight = 450.0
    public static let folderCardGap = 10.0
    /// How close a card may come to the screen's edges.
    static let cardMargin = 8.0
    /// How far the Dock stands above the bottom edge of the screen.
    public static let screenGap = 4.0

    /// Size of each icon, in Dock order.
    public let sizes: [Double]
    /// Where the bar starts, along its length.
    public let minX: Double
    /// The bar's length: its width at the bottom, its height at a side.
    public let width: Double

    public var centerX: Double {
        minX + width / 2
    }

    public init(count: Int, base: Double, magnified: Double, pointer: Double? = nil) {
        let step = base + Self.spacing
        let firstSlot = -Self.restWidth(count: count, base: base) / 2 + Self.padding - Self.spacing / 2
        let sizes = (0 ..< count).map { index in
            pointer.map { pointer in
                let center = firstSlot + (Double(index) + 0.5) * step
                return DockMagnification.size(
                    distance: pointer - center,
                    base: base,
                    magnified: max(magnified, base)
                )
            } ?? base
        }
        // The spot under the pointer stays where it is: icons left of it push the bar's left edge out and
        // icons right of it push the right edge out, so what the pointer is on does not slide away.
        let anchor = min(max(pointer ?? firstSlot, firstSlot), firstSlot + Double(count) * step)
        let toTheLeft = sizes.indices.reduce(0.0) { total, index in
            let share = (anchor - firstSlot - Double(index) * step) / step
            return total + (sizes[index] + Self.spacing) * min(max(share, 0), 1)
        }
        self.sizes = sizes
        minX = anchor - toTheLeft + Self.spacing / 2 - Self.padding
        width = sizes.reduce(0, +) + Self.spacing * Double(max(count - 1, 0)) + 2 * Self.padding
    }

    public static func restWidth(count: Int, base: Double) -> Double {
        Double(count) * base + spacing * Double(max(count - 1, 0)) + 2 * padding
    }

    public static func restHeight(base: Double) -> Double {
        base + indicator + 2 * padding
    }

    /// How far icons rise above the bar's top edge at most, with magnification on or off.
    public static func growth(_ settings: DockSettings) -> Double {
        settings.magnifies ? max(settings.magnifiedSize - settings.iconSize, 0) : 0
    }

    /// The Dock window's size. Even along the bar, so every size shares one center on the pixel grid.
    public static func windowSize(for space: DockSpace, count: Int, settings: DockSettings) -> CGSize {
        let base = settings.iconSize
        let growth = growth(settings)
        let isVertical = settings.position.isVertical
        var length = restWidth(count: count, base: base)
        var depth = restHeight(base: base)
        if space >= .magnified {
            // Each end only ever takes the growth on its side of the pointer.
            length += 2 * ceil(DockMagnification.reach) * growth
            depth += growth + bounce * (base + growth)
        }
        if space == .folder {
            // A card stands above a bar at the bottom and beside a bar at a side.
            length = max(length, isVertical ? folderCardHeight : folderCardWidth)
            depth += (isVertical ? folderCardWidth : folderCardHeight) + folderCardGap
        }
        let even = ceil(length / 2) * 2
        return isVertical ? CGSize(width: ceil(depth), height: even) : CGSize(width: even, height: ceil(depth))
    }

    /// Where the Dock window goes. Every size shares the same middle and edge, so the bar stays exactly where it
    /// is when the window changes.
    ///
    /// - Parameter topInset: The menu bar's height: a Dock at a side is centered in what is left below it.
    /// - Parameter isRevealed: False moves the window just past the screen's edge.
    public static func windowFrame(
        size: CGSize,
        position: DockPosition,
        screen: CGRect,
        topInset: Double,
        isRevealed: Bool = true
    ) -> CGRect {
        let middleY = (screen.minY + screen.maxY - topInset) / 2
        let origin = switch position {
        case .bottom:
            CGPoint(
                x: screen.midX - size.width / 2,
                y: isRevealed ? screen.minY + screenGap : screen.minY - size.height
            )
        case .left:
            CGPoint(
                x: isRevealed ? screen.minX + screenGap : screen.minX - size.width,
                y: middleY - size.height / 2
            )
        case .right:
            CGPoint(
                x: isRevealed ? screen.maxX - screenGap - size.width : screen.maxX,
                y: middleY - size.height / 2
            )
        }
        return CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
    }

    /// How far along the bar a slot's middle lies at rest, measured from the middle of the Dock.
    public static func slotCenter(_ index: Int, count: Int, base: Double) -> Double {
        let step = base + spacing
        return -restWidth(count: count, base: base) / 2 + padding + base / 2 + Double(index) * step
    }

    /// How far a card moves along the bar to stand by its tile and still fit in the window.
    public static func cardOffset(center: Double, cardLength: Double, windowLength: Double) -> Double {
        let reach = max((windowLength - cardLength) / 2, 0)
        return min(max(center, -reach), reach)
    }

    /// Where a widget's card goes: past the tallest an icon can grow, centered on the pointer and kept on screen.
    ///
    /// - Parameter bar: The Dock window at rest.
    /// - Parameter visible: The part of the screen a card may use.
    public static func cardFrame(
        size: CGSize,
        pointer: CGPoint,
        bar: CGRect,
        settings: DockSettings,
        visible: CGRect
    ) -> CGRect {
        let reach = growth(settings) + folderCardGap
        func fit(_ value: Double, _ low: Double, _ high: Double) -> Double {
            min(max(value, low + cardMargin), max(high - cardMargin, low + cardMargin))
        }
        let alongX = fit(pointer.x - size.width / 2, visible.minX, visible.maxX - size.width)
        let alongY = fit(pointer.y - size.height / 2, visible.minY, visible.maxY - size.height)
        let origin = switch settings.position {
        case .bottom: CGPoint(x: alongX, y: bar.maxY + reach)
        case .left: CGPoint(x: bar.maxX + reach, y: alongY)
        case .right: CGPoint(x: bar.minX - reach - size.width, y: alongY)
        }
        return CGRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
    }

    /// How deep a strip of the screen a resting Dock takes from windows. Nothing when it hides itself: the
    /// desktop then uses the whole screen.
    public static func reservedDepth(_ settings: DockSettings) -> Double {
        settings.isEnabled && !settings.autoHides ? screenGap + restHeight(base: settings.iconSize) : 0
    }
}

/// When a Dock that hides itself shows. Pure, so the rules are testable without touching the real Dock.
public enum DockAutoHide {
    /// How close to the edge counts as touching it: the pointer stops a point short of the screen's far edges.
    static let edgeReach = 1.5
    public static let slideDuration = 0.25
    /// Long enough to cross a small gap back to the bar without it sliding away.
    public static let hideDelay = Duration.milliseconds(400)

    /// True when the pointer has reached the edge the Dock hides behind, somewhere along the bar.
    public static func touchesEdge(
        _ point: CGPoint,
        barFrame: CGRect,
        position: DockPosition,
        screen: CGRect
    ) -> Bool {
        switch position {
        case .bottom:
            point.y <= screen.minY + edgeReach && point.x >= barFrame.minX && point.x <= barFrame.maxX
        case .left:
            point.x <= screen.minX + edgeReach && point.y >= barFrame.minY && point.y <= barFrame.maxY
        case .right:
            point.x >= screen.maxX - edgeReach && point.y >= barFrame.minY && point.y <= barFrame.maxY
        }
    }

    /// True when the pointer is on the Dock or in the gap between it and the screen's edge.
    public static func isOver(_ point: CGPoint, frame: CGRect) -> Bool {
        frame.insetBy(dx: -DockBarLayout.screenGap, dy: -DockBarLayout.screenGap).contains(point)
    }

    /// Whether the Dock should be showing now.
    ///
    /// - Parameter isHeld: Something in the Dock needs it to stay, such as an open card or menu, or a launch.
    public static func isRevealed(
        autoHides: Bool,
        wasRevealed: Bool,
        isOverDock: Bool,
        touchesEdge: Bool,
        isHeld: Bool
    ) -> Bool {
        guard autoHides else { return true }
        return isHeld || touchesEdge || (wasRevealed && isOverDock)
    }
}

/// Icon growth near the pointer.
public enum DockMagnification {
    /// Reach in tiles, so the next two icons land near the design's 1.35× and 1.12× of a 1.6× peak.
    static let reach = 2.75

    /// Size of an icon whose center is `distance` points from the pointer.
    ///
    /// A raised cosine has no kink at its edge, so an icon starts growing without a visible step.
    public static func size(distance: Double, base: Double, magnified: Double) -> Double {
        let radius = reach * (base + DockBarLayout.spacing)
        guard abs(distance) < radius else { return base }
        let closeness = (1 + cos(abs(distance) / radius * .pi)) / 2
        return base + (magnified - base) * closeness
    }
}

/// What the Dock shows right now. The app updates it and the view follows, so a change never has to
/// rebuild the view and lose the pointer or an open folder.
@MainActor
@Observable
public final class DockLiveState {
    public var settings: DockSettings
    /// Paths of Dock apps that are running, as stored in the settings.
    public var running: Set<String> = []
    /// Paths of Dock apps that were clicked and have not started yet.
    public var launching: Set<String> = []
    /// The room along the screen's edge. Unlimited until the app has measured a screen.
    public var available = Double.infinity
    /// The set of widgets wanted.
    public var page = 0
    /// The folder or stack open above the Dock, by item id.
    public var openCard: String?
    /// What each stack holds, by folder path. Filled only for stacks in the Dock.
    public var files: [String: [DockFile]] = [:]

    public init(settings: DockSettings = DockSettings()) {
        self.settings = settings
    }

    public var arrangement: DockArrangement {
        DockArrangement(items: settings.items, iconSize: settings.iconSize, length: available, page: page)
    }

    /// The settings as shown: icons may have shrunk to fit the screen.
    public var fittedSettings: DockSettings {
        var fitted = settings
        fitted.iconSize = arrangement.iconSize
        return fitted
    }
}
