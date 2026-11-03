import Foundation

public enum SensorGroup: String, Codable, CaseIterable, Sendable {
    case cpuPerformance, cpuEfficiency, gpu, soc, battery, storage, power, ambient, other

    /// Maps an SMC temperature key to a group. Prefixes are case-sensitive.
    public init(key: String) {
        switch key.prefix(2) {
        case "Tp": self = .cpuPerformance
        case "Te": self = .cpuEfficiency
        case "Tg": self = .gpu
        case "Ts", "Th", "TS": self = .soc
        case "TB": self = .battery
        case "TH": self = .storage
        case "TP", "TR", "TV": self = .power
        case "Ta", "TA": self = .ambient
        default: self = .other
        }
    }
}

public struct SensorReading: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        key
    }

    public var key: String
    public var group: SensorGroup
    public var celsius: Double

    public init(key: String, group: SensorGroup, celsius: Double) {
        self.key = key
        self.group = group
        self.celsius = celsius
    }
}

public struct FanReading: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var rpm: Double
    public var minimum: Double
    public var maximum: Double
    public var target: Double
    public var isManual: Bool

    /// Speed as a share of the fan's own range.
    public var share: Double {
        maximum > minimum ? min(max((rpm - minimum) / (maximum - minimum), 0), 1) : 0
    }
}

public struct SensorSample: Codable, Sendable, Equatable {
    public var readings: [SensorReading]
    public var fans: [FanReading]

    public init(readings: [SensorReading], fans: [FanReading]) {
        self.readings = readings
        self.fans = fans
    }

    public func average(of groups: Set<SensorGroup>) -> Double? {
        let values = readings.filter { groups.contains($0.group) }.map(\.celsius)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Mean of all CPU core sensors: the value the menu bar shows by default.
    public var averageCPU: Double? {
        average(of: [.cpuPerformance, .cpuEfficiency])
    }

    public var averageGPU: Double? {
        average(of: [.gpu])
    }

    public var averageSoC: Double? {
        average(of: [.soc])
    }

    public var averageFanRPM: Double? {
        fans.isEmpty ? nil : fans.map(\.rpm).reduce(0, +) / Double(fans.count)
    }

    /// Unused keys report zero or a negative placeholder, disconnected ones run far above any real value.
    public static func isPlausible(_ celsius: Double) -> Bool {
        celsius > 5 && celsius < 130
    }
}

/// Reads temperature and fan keys. The key list is discovered once because enumeration is slow.
public final class SensorReader: Sendable {
    private let client: SMCClient
    private let temperatureKeys: [String]
    private let fanCount: Int

    public init?() {
        guard let client = SMCClient() else { return nil }
        self.client = client
        temperatureKeys = client.keys(withPrefixes: ["T"]).filter {
            client.read($0)?.number.map(SensorSample.isPlausible) == true
        }
        fanCount = Int(client.read("FNum")?.number ?? 0)
    }

    public func sample() -> SensorSample {
        let readings = temperatureKeys.compactMap { key -> SensorReading? in
            guard let celsius = client.read(key)?.number, SensorSample.isPlausible(celsius) else { return nil }
            return SensorReading(key: key, group: SensorGroup(key: key), celsius: celsius)
        }
        return SensorSample(readings: readings, fans: (0 ..< fanCount).compactMap(fan))
    }

    private func fan(_ index: Int) -> FanReading? {
        func value(_ suffix: String) -> Double? {
            client.read("F\(index)\(suffix)")?.number
        }
        guard let rpm = value("Ac") else { return nil }
        return FanReading(
            id: index,
            rpm: rpm,
            minimum: value("Mn") ?? 0,
            maximum: value("Mx") ?? 0,
            target: value("Tg") ?? 0,
            isManual: (value("Md") ?? 0) != 0
        )
    }
}
