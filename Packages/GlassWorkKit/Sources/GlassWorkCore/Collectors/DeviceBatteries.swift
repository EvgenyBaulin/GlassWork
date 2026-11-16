import Foundation

public struct DeviceBattery: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var kind: Kind
    public var charge: Double
    /// `system_profiler` reports no charging flag for accessories, so this is inferred from the charge
    /// rising between two reads (see `DeviceBatteryReader.marking`).
    public var isCharging = false

    public init(name: String, kind: Kind, charge: Double, isCharging: Bool = false) {
        self.name = name
        self.kind = kind
        self.charge = charge
        self.isCharging = isCharging
    }

    private enum CodingKeys: String, CodingKey {
        case name, kind, charge, isCharging
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(Kind.self, forKey: .kind)
        charge = try values.decode(Double.self, forKey: .charge)
        // Snapshots written before the flag existed have no such key.
        isCharging = try values.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
    }

    public enum Kind: String, Codable, Sendable {
        case headphones, mouse, keyboard, trackpad, other

        init(minorType: String?, name: String) {
            let text = "\(minorType ?? "") \(name)".lowercased()
            if text.contains("headphone") || text.contains("airpods") || text.contains("headset") {
                self = .headphones
            } else if text.contains("mouse") {
                self = .mouse
            } else if text.contains("keyboard") {
                self = .keyboard
            } else if text.contains("trackpad") {
                self = .trackpad
            } else {
                self = .other
            }
        }
    }
}

/// Batteries of connected accessories, lowest first.
public enum DeviceBatteryReader {
    /// Parses `system_profiler SPBluetoothDataType -json`.
    public static func parseBluetooth(_ json: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let devices = sections.first?["device_connected"] as? [[String: [String: Any]]]
        else { return [] }
        return sorted(devices.flatMap { $0.compactMap(device) })
    }

    private static func device(name: String, info: [String: Any]) -> DeviceBattery? {
        let keys = ["device_batteryLevelMain", "device_batteryLevel", "device_batteryLevelLeft"]
        guard let text = keys.lazy.compactMap({ info[$0] as? String }).first,
              let percent = Double(text.replacing("%", with: ""))
        else { return nil }
        return DeviceBattery(
            name: name,
            kind: DeviceBattery.Kind(minorType: info["device_minorType"] as? String, name: name),
            charge: percent / 100
        )
    }

    /// A device is charging when its charge rose since the last read, and stays so until it drops.
    public static func marking(_ devices: [DeviceBattery], previous: [DeviceBattery]) -> [DeviceBattery] {
        devices.map { device in
            guard let before = previous.first(where: { $0.name == device.name }) else { return device }
            var marked = device
            marked.isCharging = device.charge > before.charge + 0.001
                || (before.isCharging && device.charge >= before.charge - 0.001)
            return marked
        }
    }

    public static func sorted(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        devices.sorted { $0.charge < $1.charge }
    }

    public static func read(using runner: ProcessRunning = ProcessRunner()) async -> [DeviceBattery] {
        let output = try? await runner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 10
        )
        return parseBluetooth(Data((output?.stdout ?? "").utf8))
    }
}
