import Foundation

/// Short durations such as "3d 4h", "2h 9m" or "45s" with the two largest units.
public enum CompactDuration {
    public static func format(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let days = total / 86400
        let hours = total % 86400 / 3600
        let minutes = total % 3600 / 60
        let seconds = total % 60
        switch total {
        case 86400...: return "\(days)d \(hours)h"
        case 3600...: return "\(hours)h \(minutes)m"
        case 60...: return "\(minutes)m"
        default: return "\(seconds)s"
        }
    }
}
