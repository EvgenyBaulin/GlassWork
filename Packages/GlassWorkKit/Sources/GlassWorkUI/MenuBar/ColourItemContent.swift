import GlassWorkCore
import SwiftUI

/// The Colours item: a swatch of the last colour picked and its hex, and "Copied" for a moment after a pick.
extension ItemContent {
    /// How long the item says "Copied" after a colour was copied.
    public static let colourCopiedFlash: TimeInterval = 3

    static func colours(_ store: EverydayStore, at date: Date = Date()) -> ItemContent {
        let copied = loc("Copied")
        // The hex is shorter than the word in some languages, and the item keeps one width.
        let template = copied.count > 7 ? copied : "#000000"
        guard let last = store.data.colors.first else {
            var empty = ItemContent(figure: "—", template: template)
            empty.isDimmed = true
            return empty
        }
        var content = ItemContent(figure: last, template: template)
        content.symbol = "circle.fill"
        content.swatch = Color(hex: last)
        content.detail = loc("Option-click for the history")
        if let copiedAt = store.lastColourCopy, date.timeIntervalSince(copiedAt) < colourCopiedFlash {
            content.figure = copied
        }
        return content
    }
}
