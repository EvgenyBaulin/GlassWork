import Foundation

/// Written by the app on every refresh so widgets can tell how fresh the shared data is.
public struct Heartbeat: Codable, Equatable, Sendable {
    public static let key = "heartbeat"

    public var updatedAt: Date
    public var bootTime: Date

    public init(updatedAt: Date, bootTime: Date) {
        self.updatedAt = updatedAt
        self.bootTime = bootTime
    }
}
