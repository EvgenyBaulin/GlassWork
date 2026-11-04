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
/// Positions are measured from the middle of the Dock, which never moves. The pointer has to be read in
/// that same frame: read inside the bar, it would shift as the bar widens and feed back into the sizes.
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
    /// How far the Dock stands above the bottom edge of the screen.
    public static let screenGap = 4.0

    /// Width of each icon, in Dock order.
    public let sizes: [Double]
    /// Left edge of the bar.
    public let minX: Double
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

    /// The Dock window's size. Even, so every size shares one center on the pixel grid.
    public static func windowSize(for space: DockSpace, count: Int, settings: DockSettings) -> CGSize {
        let base = settings.iconSize
        let growth = growth(settings)
        var width = restWidth(count: count, base: base)
        var height = restHeight(base: base)
        if space >= .magnified {
            // Each side only ever takes the growth on its side of the pointer.
            width += 2 * ceil(DockMagnification.reach) * growth
            height += growth + bounce * (base + growth)
        }
        if space == .folder {
            width = max(width, folderCardWidth)
            height += folderCardHeight + folderCardGap
        }
        return CGSize(width: ceil(width / 2) * 2, height: ceil(height))
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

    public init(settings: DockSettings = DockSettings()) {
        self.settings = settings
    }
}
