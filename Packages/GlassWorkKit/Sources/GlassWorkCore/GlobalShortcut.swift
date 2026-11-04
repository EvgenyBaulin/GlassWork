import Foundation

/// A key combination that works from any app. It stores plain numbers, so it can be saved and tested without
/// the system.
public struct GlobalShortcut: Codable, Hashable, Sendable {
    /// A key by its place on the keyboard, the way macOS numbers it. The place stays the same when the layout
    /// changes, so ⌃⌥Q still works while the keyboard types Russian.
    public struct Key: Codable, Hashable, Sendable {
        public let code: Int

        public init(code: Int) {
            self.code = code
        }

        public static let leftArrow = Key(code: 123)
        public static let rightArrow = Key(code: 124)
        public static let downArrow = Key(code: 125)
        public static let upArrow = Key(code: 126)
        public static let returnKey = Key(code: 36)
        public static let space = Key(code: 49)
        public static let delete = Key(code: 51)
        public static let escape = Key(code: 53)
        public static let letterC = Key(code: 8)
        public static let letterD = Key(code: 2)
        public static let letterG = Key(code: 5)
        public static let letterH = Key(code: 4)
        public static let letterI = Key(code: 34)
        public static let letterJ = Key(code: 38)
        public static let letterK = Key(code: 40)
        public static let letterQ = Key(code: 12)
        public static let letterU = Key(code: 32)
        public static let letterV = Key(code: 9)
        public static let digit2 = Key(code: 19)

        private static let labels: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
            13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
            35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
            46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 76: "⌅", 115: "↖", 116: "⇞",
            117: "⌦", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        ]

        private static let functionKeys: [Int: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10, 103: 11, 111: 12,
            105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
        ]

        /// F-keys are the only ones that can stand alone: they type nothing.
        public var isFunctionKey: Bool {
            Self.functionKeys[code] != nil
        }

        public var label: String {
            if let number = Self.functionKeys[code] {
                return "F\(number)"
            }
            return Self.labels[code] ?? "#\(code)"
        }
    }

    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
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

    /// Shift alone is not enough: a global ⇧A would stop capital letters from being typed.
    public var hasRequiredModifier: Bool {
        key.isFunctionKey || !modifiers.isDisjoint(with: [.control, .option, .command])
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
