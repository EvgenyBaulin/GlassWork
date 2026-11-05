import Foundation

/// When Keep Awake stops by itself.
public struct KeepAwakeRule: Sendable, Equatable {
    /// Zero keeps it on until it is turned off.
    public var minutes = 0
    /// Zero never stops for the battery.
    public var batteryFloor = 20

    public init() {}

    public init(options: [String: String]) {
        minutes = max(options.number(ItemOption.keepAwakeMinutes, default: 0), 0)
        batteryFloor = max(options.number(ItemOption.keepAwakeBatteryFloor, default: 20), 0)
    }

    public func end(from date: Date) -> Date? {
        minutes > 0 ? date.addingTimeInterval(TimeInterval(minutes) * 60) : nil
    }

    /// A Mac on power keeps going, whatever its charge.
    public func shouldStop(endingAt end: Date?, at date: Date, battery: BatterySample?) -> Bool {
        if let end, date >= end {
            return true
        }
        guard let battery, !battery.isOnAC, batteryFloor > 0 else { return false }
        return battery.charge * 100 < Double(batteryFloor)
    }
}

/// What happens when a timer reaches zero.
public struct TimerAlert: Sendable, Equatable {
    public static let noSound = "none"
    public static let defaultSound = "Glass"

    public var sound = TimerAlert.defaultSound
    public var notifies = true

    public init() {}

    public init(options: [String: String]) {
        sound = options[ItemOption.timerSound] ?? Self.defaultSound
        notifies = options.flag(ItemOption.timerNotifies, default: true)
    }

    /// The name of a system sound, or nil for silence.
    public var soundName: String? {
        sound == Self.noSound ? nil : sound
    }
}
