import Foundation

/// One place in the bar. Every slot is one even step, so the bar's layout and hover stay as they are.
public enum DockSlot: Sendable, Equatable, Identifiable {
    case item(DockItem)
    case previousPage
    case nextPage

    public var id: String {
        switch self {
        case let .item(item): item.id
        case .previousPage: "previous-page"
        case .nextPage: "next-page"
        }
    }
}

/// What the bar shows in the room it has. Pure, so paging is testable without a screen.
///
/// Apps and folders come first, then widgets, then stacks, as in the design. Widgets that do not fit are shown a
/// set at a time. Apps and stacks never page: when even they do not fit, icons shrink.
public struct DockArrangement: Sendable, Equatable {
    /// Below this an icon can no longer be told apart.
    public static let smallestIcon = 20.0
    /// The previous and next buttons.
    private static let pagerSlots = 2

    public let slots: [DockSlot]
    /// Slots followed by a divider. Dividers sit in the gap between slots and take no room of their own.
    public let dividers: Set<Int>
    public let iconSize: Double
    public let page: Int
    public let pageCount: Int
    /// Widgets not in the set on show.
    public let hiddenWidgets: Int

    /// - Parameter length: The room along the screen's edge.
    /// - Parameter page: The set of widgets wanted. A page that no longer exists falls back to the last one.
    public init(items: [DockItem], iconSize: Double, length: Double, page: Int = 0) {
        let apps = items.filter(\.isAppLike)
        let widgets = items.filter(\.isWidget)
        let stacks = items.filter(\.isStack)
        let fixed = apps.count + stacks.count

        var size = iconSize
        var set = widgets
        var current = 0
        var count = 1
        if DockBarLayout.restWidth(count: items.count, base: iconSize) > length {
            let needsPager = !widgets.isEmpty
            let least = fixed + (needsPager ? 1 + Self.pagerSlots : 0)
            size = min(iconSize, Self.iconSize(toFit: least, in: length))
            if needsPager {
                let room = max(Self.capacity(base: size, length: length) - fixed - Self.pagerSlots, 1)
                count = (widgets.count + room - 1) / room
                current = min(max(page, 0), count - 1)
                set = Array(widgets[(current * room) ..< min((current + 1) * room, widgets.count)])
            }
        }

        var slots = apps.map(DockSlot.item)
        var dividers = Set<Int>()
        func close() {
            if !slots.isEmpty {
                dividers.insert(slots.count - 1)
            }
        }
        if !set.isEmpty {
            close()
            if current > 0 {
                slots.append(.previousPage)
            }
            slots += set.map(DockSlot.item)
            if count > 1 {
                slots.append(.nextPage)
            }
        }
        if !stacks.isEmpty {
            close()
            slots += stacks.map(DockSlot.item)
        }
        self.slots = slots
        self.dividers = dividers
        self.iconSize = size
        self.page = current
        pageCount = count
        hiddenWidgets = widgets.count - set.count
    }

    private static func capacity(base: Double, length: Double) -> Int {
        let room = length - 2 * DockBarLayout.padding + DockBarLayout.spacing
        return Int((room / (base + DockBarLayout.spacing)).rounded(.down))
    }

    private static func iconSize(toFit count: Int, in length: Double) -> Double {
        guard count > 0 else { return .infinity }
        let room = length - 2 * DockBarLayout.padding + DockBarLayout.spacing
        return max((room / Double(count) - DockBarLayout.spacing).rounded(.down), smallestIcon)
    }
}

private extension DockItem {
    var isAppLike: Bool {
        switch self {
        case .app, .folder: true
        case .widget, .stack: false
        }
    }

    var isWidget: Bool {
        if case .widget = self {
            return true
        }
        return false
    }

    var isStack: Bool {
        if case .stack = self {
            return true
        }
        return false
    }
}
