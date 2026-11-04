import Foundation

/// What a Window Tiles shortcut does.
public enum TileCommand: Hashable, Sendable {
    case place(TileLayout)
    case previousDisplay
    case nextDisplay

    public static var all: [TileCommand] {
        TileLayout.allCases.map(TileCommand.place) + [.previousDisplay, .nextDisplay]
    }

    public var shortcut: GlobalShortcut {
        switch self {
        case let .place(layout): GlobalShortcut([.control, .option], layout.key)
        case .previousDisplay: GlobalShortcut([.control, .option, .command], .leftArrow)
        case .nextDisplay: GlobalShortcut([.control, .option, .command], .rightArrow)
        }
    }
}

private extension TileLayout {
    var key: GlobalShortcut.Key {
        switch self {
        case .leftHalf: .leftArrow
        case .rightHalf: .rightArrow
        case .topHalf: .upArrow
        case .bottomHalf: .downArrow
        case .fullScreen: .returnKey
        case .center: .letterC
        case .firstThird: .letterD
        case .lastThird: .letterG
        case .topLeft: .letterU
        case .topRight: .letterI
        case .bottomLeft: .letterJ
        case .bottomRight: .letterK
        }
    }
}
