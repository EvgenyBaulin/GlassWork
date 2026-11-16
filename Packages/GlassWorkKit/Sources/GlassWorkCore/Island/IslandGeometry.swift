import Foundation

public struct IslandScreen: Sendable, Equatable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryLeftWidth: CGFloat?
    public var auxiliaryRightWidth: CGFloat?
    public var menuBarHeight: CGFloat

    public init(
        frame: CGRect, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat? = nil,
        auxiliaryRightWidth: CGFloat? = nil, menuBarHeight: CGFloat
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.menuBarHeight = menuBarHeight
    }
}

public struct IslandWings: Sendable, Equatable {
    public var left: CGFloat
    public var right: CGFloat
    public var isLeftIconOnly: Bool
    public var movesLabelRight: Bool
}

public struct IslandGeometry: Sendable, Equatable {
    public let notch: CGRect
    public let hasNotch: Bool

    public init(screen: IslandScreen) {
        let width: CGFloat
        let height: CGFloat
        if let left = screen.auxiliaryLeftWidth, let right = screen.auxiliaryRightWidth {
            hasNotch = true
            width = max(screen.frame.width - left - right, 0)
            height = max(screen.safeAreaTop, 0)
        } else {
            hasNotch = false
            width = 0
            height = max(screen.menuBarHeight, 0)
        }
        notch = CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    public var peekFrame: CGRect {
        CGRect(x: notch.minX - 6, y: notch.minY - 4, width: notch.width + 12, height: notch.height + 4)
    }

    /// Where a file drag opens the drop zone: the notch with a margin at the sides and a little below, small
    /// enough that dragging along the menu bar does not trigger it.
    public var dropTriggerFrame: CGRect {
        CGRect(x: notch.minX - 40, y: notch.minY - 10, width: notch.width + 80, height: notch.height + 10)
    }

    public func compactFrame(leftWing: CGFloat, rightWing: CGFloat) -> CGRect {
        CGRect(
            x: notch.minX - max(leftWing, 0), y: notch.minY,
            width: notch.width + max(leftWing, 0) + max(rightWing, 0), height: notch.height
        )
    }

    public func expandedFrame(size: CGSize) -> CGRect {
        CGRect(
            x: notch.midX - max(size.width, 0) / 2, y: notch.maxY - max(size.height, 0),
            width: max(size.width, 0), height: max(size.height, 0)
        )
    }

    // Keep the collision inputs together so both wings use the same menu bar bounds.
    // swiftlint:disable:next function_parameter_count
    public static func wings(
        appMenuMaxX: CGFloat, statusItemsMinX: CGFloat, notch: CGRect,
        wanted left: CGFloat, wanted right: CGFloat, iconOnly: CGFloat
    ) -> IslandWings {
        let availableLeft = max(notch.minX - appMenuMaxX, 0)
        let movesLabel = max(left, 0) > availableLeft
        let iconWidth = min(max(iconOnly, 0), max(left, 0))
        let actualLeft = movesLabel ? (iconWidth <= availableLeft ? iconWidth : 0) : max(left, 0)
        return IslandWings(
            left: actualLeft, right: min(max(right, 0), max(statusItemsMinX - notch.maxX, 0)),
            isLeftIconOnly: movesLabel && actualLeft > 0, movesLabelRight: movesLabel
        )
    }
}
