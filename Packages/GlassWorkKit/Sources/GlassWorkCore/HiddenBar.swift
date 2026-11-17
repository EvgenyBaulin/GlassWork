import Foundation

/// How long the pointer has to rest at the separator before the hidden items open.
public enum HiddenBarHoverDelay: Double, Codable, CaseIterable, Sendable {
    case short = 0.3
    case medium = 0.6
    case long = 1
}

/// What the Hidden Bar shows.
public enum HiddenBarPhase: Sendable, Equatable {
    /// Everything left of the separator is out of sight.
    case collapsed
    /// The hidden items are shown; the always-hidden section is not.
    case revealed
    /// The always-hidden section is shown as well.
    case revealedAll
}

/// A separator is either a thin mark or wide enough to push everything left of it off the screen.
public enum HiddenBarSeparatorLength: Sendable, Equatable {
    case thin
    case wide
}

/// The lengths to give the two separators. No always-hidden separator means that section is off.
public struct HiddenBarLayout: Sendable, Equatable {
    public var separator: HiddenBarSeparatorLength
    public var alwaysHidden: HiddenBarSeparatorLength?
}

/// Where the pointer counts as being at the separator: the menu bar's height, a little either side of it.
public enum HiddenBarZone {
    public static let width: CGFloat = 28

    /// Cheap: nothing but comparisons, and the height test comes first.
    public static func contains(
        _ point: CGPoint,
        separatorMaxX: CGFloat,
        screenMaxY: CGFloat,
        barHeight: CGFloat
    ) -> Bool {
        guard point.y >= screenMaxY - barHeight, point.y <= screenMaxY else { return false }
        return point.x >= separatorMaxX - width && point.x <= separatorMaxX + 2
    }
}

/// Which hidden items are shown, and when they go back. The clock is passed in, so it is tested without waiting.
public struct HiddenBarMachine: Sendable, Equatable {
    public private(set) var phase = HiddenBarPhase.revealed
    private var settings = HidingSettings()
    private var collapseAt: Date?
    private var hoverSince: Date?
    private var openedByHover = false

    public init() {}

    public var isCollapsed: Bool {
        phase == .collapsed
    }

    public var layout: HiddenBarLayout {
        guard settings.isEnabled else { return HiddenBarLayout(separator: .thin, alwaysHidden: nil) }
        guard settings.hasAlwaysHidden else {
            return HiddenBarLayout(separator: isCollapsed ? .wide : .thin, alwaysHidden: nil)
        }
        switch phase {
        case .collapsed: return HiddenBarLayout(separator: .wide, alwaysHidden: .thin)
        case .revealed: return HiddenBarLayout(separator: .thin, alwaysHidden: .wide)
        case .revealedAll: return HiddenBarLayout(separator: .thin, alwaysHidden: .thin)
        }
    }

    /// The next moment `tick` has something to do, so the caller sleeps until then instead of polling.
    public var nextDeadline: Date? {
        let dwell = hoverSince.map { $0.addingTimeInterval(settings.hoverDelay.rawValue) }
        return [collapseAt, dwell].compactMap(\.self).min()
    }

    /// Turning the feature on starts collapsed. Turning it off, or the always-hidden section off, undoes what it did.
    public mutating func configure(_ new: HidingSettings) {
        let turnedOn = new.isEnabled && !settings.isEnabled
        settings = new
        if turnedOn {
            phase = .collapsed
        } else if !new.isEnabled {
            phase = .revealed
        } else if !new.hasAlwaysHidden, phase == .revealedAll {
            phase = .revealed
        }
        if !new.showsOnHover || !new.isEnabled {
            hoverSince = nil
        }
        if isCollapsed || !new.isEnabled {
            collapseAt = nil
        }
    }

    /// A click on the separator, or the shortcut. Option opens the always-hidden section as well.
    public mutating func toggle(option: Bool, now: Date) {
        guard settings.isEnabled else { return }
        let wantsAll = option && settings.hasAlwaysHidden
        switch phase {
        case .collapsed:
            open(wantsAll ? .revealedAll : .revealed, now: now, byHover: false)
        case .revealed where wantsAll:
            open(.revealedAll, now: now, byHover: false)
        case .revealed, .revealedAll:
            close()
        }
    }

    /// For the Hub and the colour picker, which want the bar open but never close it.
    public mutating func revealIfCollapsed(now: Date) {
        guard settings.isEnabled, isCollapsed else { return }
        open(.revealed, now: now, byHover: false)
    }

    /// Call with every pointer move at the menu bar's height. `inZone` is whether it is at the separator.
    public mutating func pointerMoved(inZone: Bool, now: Date) {
        guard settings.isEnabled, settings.showsOnHover else { return }
        if !inZone {
            hoverSince = nil
        } else if isCollapsed {
            hoverSince = hoverSince ?? now
            tick(now: now, commandHeld: false, pointerInZone: true)
        } else if openedByHover {
            collapseAt = now.addingTimeInterval(Double(settings.autoHideSeconds))
        }
    }

    /// Call when `nextDeadline` has come. A collapse waits while ⌘ is held (an item may be mid-drag) and, after
    /// a hover opening, while the pointer is still at the separator.
    public mutating func tick(now: Date, commandHeld: Bool, pointerInZone: Bool) {
        guard settings.isEnabled else { return }
        if isCollapsed {
            guard settings.showsOnHover, pointerInZone, let since = hoverSince else {
                hoverSince = nil
                return
            }
            if now.timeIntervalSince(since) >= settings.hoverDelay.rawValue - 0.001 {
                open(.revealed, now: now, byHover: true)
            }
        } else if let due = collapseAt, now >= due {
            if commandHeld || (openedByHover && pointerInZone) {
                collapseAt = now.addingTimeInterval(Double(settings.autoHideSeconds))
            } else {
                close()
            }
        }
    }

    private mutating func open(_ new: HiddenBarPhase, now: Date, byHover: Bool) {
        phase = new
        openedByHover = byHover
        hoverSince = nil
        collapseAt = now.addingTimeInterval(Double(settings.autoHideSeconds))
    }

    private mutating func close() {
        phase = .collapsed
        openedByHover = false
        collapseAt = nil
    }
}
