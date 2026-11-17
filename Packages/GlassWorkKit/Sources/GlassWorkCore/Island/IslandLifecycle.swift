import Foundation

public enum IslandPhase: Sendable, Equatable {
    case idle, peek, compact, expanded
}

public struct IslandLifecycle: Sendable, Equatable {
    public static let peekDelay: TimeInterval = 0.15
    public static let expandDelay: TimeInterval = 0.3
    public static let collapseDelay: TimeInterval = 1

    public private(set) var phase = IslandPhase.idle
    public var hoverToExpand: Bool
    /// A click on the peek opens the card even with no event, to show the mini widgets.
    public var opensWidgets = false
    private var hasEvents = false
    private var enteredAt: Date?
    private var exitedAt: Date?

    public init(hoverToExpand: Bool = false) {
        self.hoverToExpand = hoverToExpand
    }

    public var nextDeadline: Date? {
        if phase == .expanded {
            return exitedAt?.addingTimeInterval(Self.collapseDelay)
        }
        guard let enteredAt else { return nil }
        if phase == .idle {
            return enteredAt.addingTimeInterval(Self.peekDelay)
        }
        return hoverToExpand && hasEvents ? enteredAt.addingTimeInterval(Self.expandDelay) : nil
    }

    public mutating func pointerEntered(at date: Date) {
        if enteredAt == nil {
            enteredAt = date
        }
        exitedAt = nil
    }

    public mutating func pointerExited(at date: Date) {
        enteredAt = nil
        if phase == .expanded {
            if exitedAt == nil {
                exitedAt = date
            }
        } else if phase == .peek {
            phase = .idle
        }
    }

    public mutating func clicked() {
        switch phase {
        case .idle: phase = .peek
        case .peek: phase = opensWidgets ? .expanded : .peek
        case .compact: phase = .expanded
        case .expanded: collapse()
        }
    }

    public mutating func escape() {
        if phase == .expanded {
            collapse()
        }
    }

    public mutating func clickedOutside() {
        if phase == .expanded {
            collapse()
        }
    }

    public mutating func eventsChanged(hasEvents: Bool) {
        self.hasEvents = hasEvents
        if phase != .expanded {
            if hasEvents {
                phase = .compact
            } else if phase == .compact {
                phase = .idle
            }
        }
    }

    public mutating func tick(at date: Date) {
        if phase == .expanded {
            if let exitedAt, date >= exitedAt.addingTimeInterval(Self.collapseDelay) {
                collapse()
            }
            return
        }
        guard let enteredAt else { return }
        if phase == .idle, date >= enteredAt.addingTimeInterval(Self.peekDelay) {
            phase = .peek
        }
        // With nothing to show, hovering only peeks: an empty card would say nothing.
        if hoverToExpand, hasEvents, date >= enteredAt.addingTimeInterval(Self.expandDelay) {
            phase = .expanded
        }
    }

    private mutating func collapse() {
        phase = hasEvents ? .compact : .idle
        enteredAt = nil
        exitedAt = nil
    }
}
