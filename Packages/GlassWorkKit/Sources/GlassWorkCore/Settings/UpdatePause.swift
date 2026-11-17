import Foundation

/// How long the user asked updates to stay paused.
public enum UpdatePause: Sendable, CaseIterable, Equatable {
    case fifteenMinutes, oneHour, untilTomorrow, indefinitely

    /// When updates resume; nil for an indefinite pause.
    public func end(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .fifteenMinutes: now.addingTimeInterval(15 * 60)
        case .oneHour: now.addingTimeInterval(60 * 60)
        case .untilTomorrow: calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0),
                matchingPolicy: .nextTime
            )
        case .indefinitely: nil
        }
    }
}
