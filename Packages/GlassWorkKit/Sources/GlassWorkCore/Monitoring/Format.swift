import Foundation
import Synchronization

/// How temperatures are written. System follows the Mac's region.
public enum TemperatureUnit: String, Codable, Sendable, CaseIterable {
    case system, celsius, fahrenheit
}

/// Text for figures. Compact fits the menu bar, precise is for panels.
public enum Format {
    private static let chosenUnit = Mutex(TemperatureUnit.system)

    /// What `temperature(_:)` writes. The app sets it from Settings, and widgets from their snapshot.
    public static var temperatureUnit: TemperatureUnit {
        get { chosenUnit.withLock { $0 } }
        set { chosenUnit.withLock { $0 = newValue } }
    }

    public static func percent(_ share: Double, style: NumberStyle = .compact) -> String {
        switch style {
        case .compact: "\(Int((share * 100).rounded()))%"
        case .precise: String(format: "%.1f%%", share * 100)
        }
    }

    /// A share of one core, so it can pass 100%. Small figures keep a decimal: 0.4% is not nothing.
    public static func corePercent(_ percent: Double) -> String {
        percent < 0.95 && percent > 0 ? String(format: "%.1f%%", percent) : "\(Int(percent.rounded()))%"
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

    /// For lists of apps: 6.2 GB, 620 MB. A second decimal would only flicker there.
    public static func size(_ value: Double) -> String {
        let (scaled, unit) = scale(value)
        return String(format: scaled < 100 ? "%.1f %@" : "%.0f %@", scaled, unit)
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

    /// The same speed in bits, the way network providers quote it.
    public static func bitRate(_ bytesPerSecond: Double, style: NumberStyle = .compact) -> String {
        let (scaled, unit) = scale(bytesPerSecond * 8)
        let prefix = unit.dropLast()
        switch style {
        case .compact:
            return "\(number(scaled))\(prefix)b/s"
        case .precise:
            return String(format: "%.1f %@bit/s", scaled, String(prefix))
        }
    }

    public static func temperature(_ celsius: Double) -> String {
        temperature(celsius, unit: temperatureUnit)
    }

    public static func temperature(_ celsius: Double, unit: TemperatureUnit) -> String {
        let measurement = Measurement(value: celsius, unit: UnitTemperature.celsius)
        let shown = unit == .fahrenheit ? measurement.converted(to: .fahrenheit) : measurement
        // The narrow form can drop the letter, and someone who picked a unit should see it.
        return shown.formatted(.measurement(
            width: unit == .system ? .narrow : .abbreviated,
            usage: unit == .system ? .weather : .asProvided,
            numberFormatStyle: .number.precision(.fractionLength(0))
        ))
    }

    public static func rpm(_ value: Double) -> String {
        "\(Int(value.rounded()))"
    }

    /// With a thousands separator, for the large figure in a panel.
    public static func groupedRPM(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number.grouping(.automatic))
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
