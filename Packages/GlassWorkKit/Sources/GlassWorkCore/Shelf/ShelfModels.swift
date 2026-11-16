import Foundation
import UniformTypeIdentifiers

/// What a shelf item is, for choosing a glyph when there is no thumbnail.
public enum ShelfKind: String, Codable, Sendable, CaseIterable {
    case folder, image, document, archive, other

    /// Decided by the file type, so a renamed file keeps the right glyph.
    public static func of(_ url: URL) -> ShelfKind {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        if values?.isDirectory == true {
            return .folder
        }
        guard let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) else { return .other }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .archive) {
            return .archive
        }
        if type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet)
        {
            return .document
        }
        return .other
    }
}

/// One file or folder on the shelf.
public struct ShelfItem: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    /// Where the file is now: the original, or the copy the shelf made.
    public var path: String
    /// Where it was dropped from. The same as `path` unless the shelf copied it.
    public var source: String
    public var byteCount: Int64
    public var added: Date
    public var kind: ShelfKind
    public var isCopy: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        path: String,
        source: String? = nil,
        byteCount: Int64,
        added: Date,
        kind: ShelfKind,
        isCopy: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.source = source ?? path
        self.byteCount = byteCount
        self.added = added
        self.kind = kind
        self.isCopy = isCopy
    }

    public var url: URL {
        URL(filePath: path)
    }
}

/// The shelf options of Settings.
public struct ShelfSettings: Sendable, Equatable {
    public static let defaultMaxItems = 20

    /// Copies files into the app's folder instead of pointing at them.
    public var copiesFiles = false
    public var maxItems = ShelfSettings.defaultMaxItems
    public var showsThumbnails = true

    public init() {}

    public init(options: [String: String]) {
        copiesFiles = options.flag(ItemOption.shelfCopiesFiles, default: false)
        maxItems = max(1, options.number(ItemOption.shelfMaxItems, default: ShelfSettings.defaultMaxItems))
        showsThumbnails = options.flag(ItemOption.shelfThumbnails, default: true)
    }
}
