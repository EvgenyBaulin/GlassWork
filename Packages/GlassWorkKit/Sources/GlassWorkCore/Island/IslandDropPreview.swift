import Foundation

/// What a file drag over the notch carries, for the drop zone.
public struct IslandDropPreview: Sendable, Equatable {
    public var names: [String]
    /// How many files are being dragged.
    public var count: Int
    /// How many items the shelf holds already.
    public var onShelf: Int

    public init(names: [String], onShelf: Int) {
        self.names = names
        count = names.count
        self.onShelf = onShelf
    }

    public init(urls: [URL], onShelf: Int) {
        self.init(names: urls.map(\.lastPathComponent), onShelf: onShelf)
    }

    /// The first two names, with how many more follow.
    public var listedNames: String {
        let shown = names.prefix(2).joined(separator: ", ")
        return count > 2 ? "\(shown) +\(count - 2)" : shown
    }
}
