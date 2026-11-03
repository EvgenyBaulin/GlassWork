import Foundation

/// Text for figures. Compact fits the menu bar, precise is for panels.
public enum Format {
    public static func percent(_ share: Double, style: NumberStyle = .compact) -> String {
        switch style {
        case .compact: "\(Int((share * 100).rounded()))%"
        case .precise: String(format: "%.1f%%", share * 100)
        }
    }

    public static func bytes(_ value: Double, style: NumberStyle = .compact) -> String {
        let (scaled, unit) = scale(value)
        switch style {
        case .compact:
            return "\(number(scaled))\(unit.prefix(1))"
        case .precise:
            return String(format: scaled < 10 ? "%.2f %@" : "%.1f %@", scaled, unit)
        }
    }

    public static func rate(_ bytesPerSecond: Double, style: NumberStyle = .compact) -> String {
        let (scaled, unit) = scale(bytesPerSecond)
        switch style {
        case .compact:
            return "\(number(scaled))\(unit.prefix(1))/s"
        case .precise:
            return String(format: "%.1f %@/s", scaled, unit)
        }
    }

    public static func temperature(_ celsius: Double) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        return measurement.formatted(
            .measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    public static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    private static func number(_ value: Double) -> String {
        value < 10 && value != value.rounded() ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    /// Decimal units, matching Finder and Activity Monitor.
    private static func scale(_ value: Double) -> (Double, String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(value, 0)
        var index = 0
        while scaled >= 1000, index < units.count - 1 {
            scaled /= 1000
            index += 1
        }
        return (scaled, units[index])
    }
}
