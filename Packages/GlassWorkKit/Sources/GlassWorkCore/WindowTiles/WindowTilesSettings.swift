import Foundation

/// Off until turned on in Settings: while off, no shortcut is taken and no window is touched.
public struct WindowTilesSettings: Codable, Sendable, Equatable {
    public var isEnabled = false
    /// Off moves the window straight away, with nothing drawn first.
    public var showsPreview = true

    public init() {}

    /// Missing keys keep their defaults, so a hand edit of one key does not reset the other.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        showsPreview = try container.decodeIfPresent(Bool.self, forKey: .showsPreview) ?? true
    }
}
