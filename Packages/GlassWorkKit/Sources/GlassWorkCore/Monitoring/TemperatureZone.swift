import Foundation

/// How worried a temperature should make the reader: below 60 °C is cool, from 80 °C is hot.
public enum TemperatureZone: String, Sendable, CaseIterable {
    case cool, warm, hot

    public static let warmFrom = 60.0
    public static let hotFrom = 80.0

    public init(celsius: Double) {
        if celsius >= Self.hotFrom {
            self = .hot
        } else if celsius >= Self.warmFrom {
            self = .warm
        } else {
            self = .cool
        }
    }
}
