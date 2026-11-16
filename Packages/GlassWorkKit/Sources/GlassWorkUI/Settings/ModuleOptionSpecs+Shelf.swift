import GlassWorkCore

/// Rows of Shelf.
extension ModuleOptionSpec {
    static var shelfRows: [ModuleOptionSpec] {
        typealias Key = ItemOption
        return [
            toggle(
                .shelf, Key.shelfCopiesFiles, "Copy files onto the shelf", "Копировать файлы на полку",
                fallback: false
            ),
            option(
                .shelf, Key.shelfMaxItems, "Max items", "Макс. файлов",
                .number(5 ... 100, step: 5, unit: ""), fallback: String(ShelfSettings.defaultMaxItems)
            ),
            toggle(.shelf, Key.shelfThumbnails, "Show thumbnails", "Показывать миниатюры", fallback: true),
        ]
    }
}
