import Foundation

/// Tells a click from a press and hold, from when the button went down and came up.
public enum PressHold {
    /// How long a press lasts before it counts as a hold.
    public static let holdDuration: TimeInterval = 0.6

    public enum Outcome: Sendable, Equatable {
        case click
        case hold
    }

    /// A press without a known start, such as a release whose press happened elsewhere, is a click.
    public static func outcome(down: Date?, released: Date) -> Outcome {
        guard let down, released.timeIntervalSince(down) >= holdDuration else { return .click }
        return .hold
    }
}
