import Foundation

public enum ThresholdAlert: String, Sendable, CaseIterable {
    case lowBattery, highTemperature
}

/// Decides when an alert fires: once per crossing, and only again after recovering past a margin.
public struct ThresholdTracker: Sendable {
    private var active: Set<ThresholdAlert> = []

    public init() {}

    /// Returns alerts that just crossed their threshold.
    public mutating func update(
        battery: BatterySample?,
        averageCPU: Double?,
        settings: AlertSettings
    ) -> [ThresholdAlert] {
        var fired: [ThresholdAlert] = []
        if let battery {
            let percent = battery.charge * 100
            let limit = Double(settings.lowBatteryPercent)
            let isLow = !battery.isCharging && percent <= limit
            track(.lowBattery, isOver: isLow, recovered: battery.isCharging || percent > limit + 5, fired: &fired)
        }
        if let averageCPU {
            let limit = Double(settings.highTemperature)
            track(.highTemperature, isOver: averageCPU >= limit, recovered: averageCPU < limit - 5, fired: &fired)
        }
        return fired
    }

    private mutating func track(
        _ alert: ThresholdAlert,
        isOver: Bool,
        recovered: Bool,
        fired: inout [ThresholdAlert]
    ) {
        if isOver, active.insert(alert).inserted {
            fired.append(alert)
        } else if recovered {
            active.remove(alert)
        }
    }
}
