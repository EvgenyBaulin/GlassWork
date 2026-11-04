import Foundation

/// Everything a global shortcut can do.
public enum ShortcutAction: Hashable, Sendable {
    case hub, quickPaste, textCapture, quickQuit
    case tile(TileCommand)

    public static var all: [ShortcutAction] {
        [.hub, .quickPaste, .textCapture, .quickQuit] + TileCommand.all.map(ShortcutAction.tile)
    }

    /// What settings.json calls it, so it must not change.
    public var id: String {
        switch self {
        case .hub: "hub"
        case .quickPaste: "quickPaste"
        case .textCapture: "textCapture"
        case .quickQuit: "quickQuit"
        case let .tile(.place(layout)): "tile.\(layout)"
        case .tile(.previousDisplay): "tile.previousDisplay"
        case .tile(.nextDisplay): "tile.nextDisplay"
        }
    }

    public var defaultShortcut: GlobalShortcut {
        switch self {
        case .hub: GlobalShortcut([.control, .option], .space)
        case .quickPaste: GlobalShortcut([.shift, .command], .letterV)
        case .textCapture: GlobalShortcut([.shift, .command], .digit2)
        case .quickQuit: GlobalShortcut([.control, .option], .letterQ)
        case let .tile(command): command.defaultShortcut
        }
    }
}

/// One change from the defaults. No shortcut means the user cleared it.
public struct ShortcutBinding: Codable, Sendable, Equatable {
    public var action: String
    public var shortcut: GlobalShortcut?

    public init(action: String, shortcut: GlobalShortcut?) {
        self.action = action
        self.shortcut = shortcut
    }
}

/// The user's shortcuts, as changes from the defaults.
///
/// A list and not a dictionary: saving merges dictionaries with what the file already holds, so a shortcut put
/// back to its default would return on the next launch.
public struct ShortcutSettings: Codable, Sendable, Equatable {
    public private(set) var bindings: [ShortcutBinding] = []

    public init() {}

    /// A broken entry from a hand edit costs that one shortcut, not the rest.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bindings = try container.decodeIfPresent([Lossy].self, forKey: .bindings)?.compactMap(\.value) ?? []
    }

    private struct Lossy: Decodable {
        let value: ShortcutBinding?

        init(from decoder: Decoder) throws {
            value = try? ShortcutBinding(from: decoder)
        }
    }

    /// Nil means the action has no shortcut.
    public func shortcut(for action: ShortcutAction) -> GlobalShortcut? {
        guard let binding = bindings.first(where: { $0.action == action.id }) else {
            return action.defaultShortcut
        }
        return binding.shortcut
    }

    public mutating func set(_ action: ShortcutAction, to shortcut: GlobalShortcut?) {
        bindings.removeAll { $0.action == action.id }
        if shortcut != action.defaultShortcut {
            bindings.append(ShortcutBinding(action: action.id, shortcut: shortcut))
        }
    }

    /// Gives `shortcut` to `action`, taking it away from whichever action held it.
    public mutating func replace(_ action: ShortcutAction, with shortcut: GlobalShortcut) {
        if let holder = holder(of: shortcut, except: action) {
            set(holder, to: nil)
        }
        set(action, to: shortcut)
    }

    public mutating func restoreDefaults() {
        bindings = []
    }

    public func holder(of shortcut: GlobalShortcut, except action: ShortcutAction) -> ShortcutAction? {
        ShortcutAction.all.first { $0 != action && self.shortcut(for: $0) == shortcut }
    }
}

/// A shortcut macOS itself uses. `name` is the English text, also the key in the string catalog.
public struct SystemShortcut: Sendable, Equatable {
    public let shortcut: GlobalShortcut
    public let name: String

    init(_ modifiers: GlobalShortcut.Modifiers, _ key: GlobalShortcut.Key, _ name: String) {
        shortcut = GlobalShortcut(modifiers, key)
        self.name = name
    }

    /// The ones people meet every day. Macs can have others, and other apps have their own: this cannot see those.
    public static let known: [SystemShortcut] = [
        SystemShortcut([.command], .space, "Spotlight"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 48), "App Switcher"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 50), "Next window"),
        SystemShortcut([.command], .letterQ, "Quit the app"),
        SystemShortcut([.command], .letterH, "Hide the app"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 46), "Minimize"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 13), "Close window"),
        SystemShortcut([.command], .letterC, "Copy"),
        SystemShortcut([.command], .letterV, "Paste"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 7), "Cut"),
        SystemShortcut([.command], GlobalShortcut.Key(code: 6), "Undo"),
        SystemShortcut([.control], .space, "Input source"),
        SystemShortcut([.control], .upArrow, "Mission Control"),
        SystemShortcut([.control], .downArrow, "App windows"),
        SystemShortcut([.control], .leftArrow, "Previous Space"),
        SystemShortcut([.control], .rightArrow, "Next Space"),
        SystemShortcut([.control, .command], .letterQ, "Lock Screen"),
        SystemShortcut([.shift, .command], GlobalShortcut.Key(code: 20), "Screenshot"),
        SystemShortcut([.shift, .command], GlobalShortcut.Key(code: 21), "Screenshot"),
        SystemShortcut([.shift, .command], GlobalShortcut.Key(code: 23), "Screenshot"),
    ]
}

/// What a newly pressed shortcut runs into.
public enum ShortcutCheck: Sendable, Equatable {
    case ok
    /// Needs ⌃, ⌥ or ⌘, unless it is an F-key.
    case needsModifier
    /// Already used by another action here; can be replaced.
    case taken(ShortcutAction)
    /// macOS uses it; can be used anyway.
    case system(name: String)

    public init(_ shortcut: GlobalShortcut, for action: ShortcutAction, in settings: ShortcutSettings) {
        if !shortcut.hasRequiredModifier {
            self = .needsModifier
        } else if let holder = settings.holder(of: shortcut, except: action) {
            self = .taken(holder)
        } else if let known = SystemShortcut.known.first(where: { $0.shortcut == shortcut }) {
            self = .system(name: known.name)
        } else {
            self = .ok
        }
    }
}

/// What a key press means while a shortcut is being recorded. Only the key and modifiers go in.
public enum ShortcutRecording: Sendable, Equatable {
    case cancel
    case clear
    case record(GlobalShortcut)

    public init(key: GlobalShortcut.Key, modifiers: GlobalShortcut.Modifiers) {
        // Bare Esc and Delete are the two controls of the field. With modifiers they are ordinary keys.
        if modifiers.isEmpty, key == .escape {
            self = .cancel
        } else if modifiers.isEmpty, key == .delete {
            self = .clear
        } else {
            self = .record(GlobalShortcut(modifiers, key))
        }
    }
}
