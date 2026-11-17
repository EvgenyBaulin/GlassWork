import CoreGraphics
import Foundation

/// A display as the frame memory sees it: enough to match a saved frame to a screen and keep it visible.
public struct DisplayInfo: Sendable, Equatable {
    public let id: UInt32
    public let name: String
    public let visibleFrame: CGRect

    public init(id: UInt32, name: String, visibleFrame: CGRect) {
        self.id = id
        self.name = name
        self.visibleFrame = visibleFrame
    }
}

/// Where a floating module window was last put, for each module and each display.
public struct DetachedPanelMemory: Codable, Sendable, Equatable {
    public struct Record: Codable, Sendable, Equatable {
        public var module: String
        public var displayID: UInt32
        public var displayName: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var savedAt: Date

        public var frame: CGRect {
            CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// Keyed by module and display, see `key(_:display:)`.
    public private(set) var records: [String: Record] = [:]

    /// Floating windows never get smaller or larger than this.
    public static let minimumSize = CGSize(width: 300, height: 220)
    public static let maximumSize = CGSize(width: 640, height: 1000)

    public init() {}

    public static func key(_ module: ModuleID, display: DisplayInfo) -> String {
        "\(module.rawValue)@\(display.id)"
    }

    /// Keeps `frame` inside `visible` and between the size limits.
    public static func clamp(_ frame: CGRect, to visible: CGRect) -> CGRect {
        let width = min(min(max(frame.width, minimumSize.width), maximumSize.width), visible.width)
        let height = min(min(max(frame.height, minimumSize.height), maximumSize.height), visible.height)
        let x = min(max(frame.minX, visible.minX), visible.maxX - width)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    public mutating func remember(_ module: ModuleID, frame: CGRect, on display: DisplayInfo, at date: Date) {
        records[Self.key(module, display: display)] = Record(
            module: module.rawValue,
            displayID: display.id,
            displayName: display.name,
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: frame.height,
            savedAt: date
        )
    }

    /// Whether the saved frame for this module and display is already `frame`.
    public func isCurrent(_ module: ModuleID, frame: CGRect, on display: DisplayInfo) -> Bool {
        records[Self.key(module, display: display)]?.frame == frame
    }

    /// The frame to open a module's window with, or nil when it has never been moved (the caller centers it).
    ///
    /// The record for the preferred display wins. Otherwise the newest record whose display is still connected
    /// is used, and when all of them are gone the newest one is brought onto the preferred display.
    public func frame(for module: ModuleID, preferred: DisplayInfo, displays: [DisplayInfo]) -> CGRect? {
        let newest = records.values.filter { $0.module == module.rawValue }.sorted { $0.savedAt > $1.savedAt }
        let connected = displays.contains { $0.id == preferred.id } ? displays : displays + [preferred]
        if let record = newest.first(where: { Self.display(for: $0, in: connected)?.id == preferred.id }) {
            return Self.clamp(record.frame, to: preferred.visibleFrame)
        }
        for record in newest {
            if let display = Self.display(for: record, in: displays) {
                return Self.clamp(record.frame, to: display.visibleFrame)
            }
        }
        guard let record = newest.first else { return nil }
        return Self.clamp(record.frame, to: preferred.visibleFrame)
    }

    /// The display a record belongs to: the same identifier first. A reconnected display may get a new
    /// identifier, so the name is used only when no identifier matches and exactly one display has that name.
    private static func display(for record: Record, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let byID = displays.first(where: { $0.id == record.displayID }) {
            return byID
        }
        let named = displays.filter { $0.name == record.displayName }
        return named.count == 1 ? named[0] : nil
    }
}
