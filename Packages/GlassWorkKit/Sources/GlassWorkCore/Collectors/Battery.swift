import Foundation
import IOKit.ps

public struct BatterySample: Codable, Sendable, Equatable {
    public var charge: Double
    public var isCharging: Bool
    public var isOnAC: Bool
    /// Minutes until empty or full; nil while macOS is still estimating.
    public var minutesRemaining: Int?
    public var health: Double?
    public var cycleCount: Int?
    public var temperature: Double?
    public var adapterWatts: Int?
}

public enum BatteryReader {
    public static func sample() -> BatterySample? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            return parse(description, smart: IORegistry.properties(ofClass: "AppleSmartBattery").first ?? [:])
        }
        return nil
    }

    /// Combines the power source description with the battery controller's registry entry.
    public static func parse(_ source: [String: Any], smart: [String: Any]) -> BatterySample {
        let current = source[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maximum = max(source[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let charging = source[kIOPSIsChargingKey] as? Bool ?? false
        let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        let minutes = source[minutesKey] as? Int ?? -1
        return BatterySample(
            charge: Double(current) / Double(maximum),
            isCharging: charging,
            isOnAC: source[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            minutesRemaining: minutes > 0 ? minutes : nil,
            health: health(smart),
            cycleCount: smart["CycleCount"] as? Int,
            temperature: (smart["Temperature"] as? Int).map { Double($0) / 100 },
            adapterWatts: (smart["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
        )
    }

    private static func health(_ smart: [String: Any]) -> Double? {
        guard let design = smart["DesignCapacity"] as? Int, design > 0,
              let actual = (smart["NominalChargeCapacity"] ?? smart["AppleRawMaxCapacity"]) as? Int
        else { return nil }
        return min(Double(actual) / Double(design), 1)
    }
}
