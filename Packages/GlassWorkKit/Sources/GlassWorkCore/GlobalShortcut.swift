import Foundation

/// A key combination that works from any app. It holds no key codes, so it can be tested without the system.
public struct GlobalShortcut: Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case leftArrow, rightArrow, upArrow, downArrow, returnKey, space
        case letterC, letterD, letterG, letterH, letterI, letterJ, letterK, letterQ, letterU, letterV
        case digit2
    }

    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public let key: Key
    public let modifiers: Modifiers

    public init(_ modifiers: Modifiers, _ key: Key) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Modifiers in the order macOS writes them in menus.
    public var label: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + key.label
    }

    /// Shortcuts that belong to other features. A new global shortcut must not take any of these.
    public static let reserved: [GlobalShortcut] = [
        // The Hub.
        GlobalShortcut([.control, .option], .space),
        // Quick paste.
        GlobalShortcut([.shift, .command], .letterV),
        // Text capture.
        GlobalShortcut([.shift, .command], .digit2),
        // Quick quit palette.
        GlobalShortcut([.control, .option], .letterQ),
        // Hidden Bar.
        GlobalShortcut([.control, .option], .letterH),
    ]
}

private extension GlobalShortcut.Key {
    var label: String {
        switch self {
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .returnKey: "↩"
        case .space: "Space"
        case .letterC: "C"
        case .letterD: "D"
        case .letterG: "G"
        case .letterH: "H"
        case .letterI: "I"
        case .letterJ: "J"
        case .letterK: "K"
        case .letterQ: "Q"
        case .letterU: "U"
        case .letterV: "V"
        case .digit2: "2"
        }
    }
}
