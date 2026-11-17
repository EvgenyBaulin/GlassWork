import Foundation

/// Which accessories count towards the Device Batteries figure. Devices are left out by name, so one that
/// has not been seen yet is included, and the default is every device.
public struct DeviceSelection: Sendable, Equatable {
    /// Names the user unticked.
    public private(set) var excluded: Set<String>
    /// Every name that has been seen, in the order they appeared, so Settings can list devices that are away.
    public private(set) var seen: [String]

    public init(options: [String: String] = [:]) {
        excluded = Set(Self.names(options[ItemOption.excludedDevices]))
        seen = Self.names(options[ItemOption.seenDevices])
    }

    public func includes(_ name: String) -> Bool {
        !excluded.contains(name)
    }

    public func filter(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        devices.filter { includes($0.name) }
    }

    /// The stored `excludedDevices` value after one device is ticked or unticked.
    public func stored(after name: String, isIncluded: Bool) -> String {
        var names = excluded
        if isIncluded {
            names.remove(name)
        } else {
            names.insert(name)
        }
        return names.sorted().joined(separator: Self.separator)
    }

    /// The stored `seenDevices` value once these devices are added, or nil when nothing is new.
    public func recording(_ devices: [DeviceBattery]) -> String? {
        var names = seen
        for name in devices.map(\.name) where !name.isEmpty && !names.contains(name) {
            names.append(name)
        }
        return names.count == seen.count ? nil : names.joined(separator: Self.separator)
    }

    /// Names can hold commas, so a line break separates them.
    private static let separator = "\n"

    private static func names(_ text: String?) -> [String] {
        text?.split(separator: "\n").map(String.init) ?? []
    }
}
