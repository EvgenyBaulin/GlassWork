import CoreWLAN

/// Which optional hardware this Mac has. Modules that need what is missing stay out of the Hub and Settings.
public struct HardwareAvailability: Sendable, Equatable {
    public var hasBattery: Bool
    public var hasWiFi: Bool
    public var hasFans: Bool

    public init(hasBattery: Bool = true, hasWiFi: Bool = true, hasFans: Bool = true) {
        self.hasBattery = hasBattery
        self.hasWiFi = hasWiFi
        self.hasFans = hasFans
    }

    /// Everything present, for tests and previews.
    public static let all = HardwareAvailability()

    /// Read once at the first use; hardware does not come and go while the app runs.
    public static let current = HardwareAvailability(
        hasBattery: BatteryReader.sample() != nil,
        hasWiFi: CWWiFiClient.shared().interface() != nil,
        hasFans: FanHardware.hasFans
    )
}
