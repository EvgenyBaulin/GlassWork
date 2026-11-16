import GlassWorkCore

/// The shelf item: the tray symbol and how many files are on it, dimmed while it is empty.
extension ItemContent {
    static func shelf(_ store: ShelfStore) -> ItemContent {
        var content = ItemContent(figure: "\(store.items.count)", template: "99")
        content.isDimmed = store.items.isEmpty
        return content
    }
}
