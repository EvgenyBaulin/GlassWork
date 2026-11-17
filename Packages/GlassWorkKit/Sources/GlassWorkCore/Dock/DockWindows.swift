import CoreGraphics
import Foundation

/// One window of an app, as the Dock's menu lists it.
public struct DockWindowItem: Equatable, Sendable, Identifiable {
    /// The window server's number for it.
    public let id: Int
    /// Nil when the window has no title or the title cannot be read: titles need Screen Recording.
    public let title: String?
    /// Its place in the list, from 1: what "Window 2" calls it when it has no title.
    public let number: Int
    public let bounds: CGRect

    public init(id: Int, title: String?, number: Int, bounds: CGRect) {
        self.id = id
        self.title = title
        self.number = number
        self.bounds = bounds
    }
}

/// Windows from the window server and from Accessibility, and which is which.
public enum DockWindows {
    /// A window as `CGWindowListCopyWindowInfo` reports it.
    public struct Raw: Equatable, Sendable {
        public var id: Int
        public var pid: Int32
        public var layer: Int
        public var bounds: CGRect
        public var title: String?
        public var alpha: Double

        public init(id: Int, pid: Int32, layer: Int, bounds: CGRect, title: String?, alpha: Double = 1) {
            self.id = id
            self.pid = pid
            self.layer = layer
            self.bounds = bounds
            self.title = title
            self.alpha = alpha
        }
    }

    /// A window as Accessibility reports it.
    public struct Element: Equatable, Sendable {
        public var title: String?
        public var frame: CGRect

        public init(title: String?, frame: CGRect) {
            self.title = title
            self.frame = frame
        }
    }

    /// Smaller than this is a tool strip or a shadow, not a window to list.
    public static let smallest = CGSize(width: 60, height: 40)

    /// The app's ordinary windows, front to back. A window with no title is numbered by its place in the list,
    /// counting the ones that have a title, so "Window 3" is always the third line of the menu.
    public static func items(from windows: [Raw], pid: Int32) -> [DockWindowItem] {
        let own = windows.filter {
            $0.pid == pid && $0.layer == 0 && $0.alpha > 0
                && $0.bounds.width >= smallest.width && $0.bounds.height >= smallest.height
        }
        return own.enumerated().map { index, window in
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return DockWindowItem(
                id: window.id,
                title: title?.isEmpty == false ? title : nil,
                number: index + 1,
                bounds: window.bounds
            )
        }
    }

    /// Which Accessibility window is this one. The window server's number cannot be turned into an element without a
    /// private call, so they are matched by where they are: same corner and size, and the title when two sit alike.
    public static func match(_ item: DockWindowItem, in elements: [Element], tolerance: CGFloat = 2) -> Int? {
        let alike = elements.indices.filter { index in
            let frame = elements[index].frame
            return abs(frame.minX - item.bounds.minX) <= tolerance && abs(frame.minY - item.bounds.minY) <= tolerance
                && abs(frame.width - item.bounds.width) <= tolerance
                && abs(frame.height - item.bounds.height) <= tolerance
        }
        if alike.count > 1, let title = item.title,
           let titled = alike.first(where: { elements[$0].title == title })
        {
            return titled
        }
        return alike.first
    }

    /// Whether a menu item is the one ⌘N chooses: key "N" with Command alone. Found by the shortcut and not the
    /// name, so it holds in every language.
    public static func isCommandN(character: String?, modifiers: Int?) -> Bool {
        character?.uppercased() == "N" && modifiers == 0
    }
}
