import Foundation

public struct GPUSample: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    /// Zero when the driver does not report it; check ``isReported`` before showing it.
    public var device: Double
    /// False when the driver gave no utilization, so the zero in ``device`` is not a real 0%.
    public var isReported: Bool
    public var renderer: Double?
    public var tiler: Double?
    public var memoryInUse: UInt64

    public init(
        name: String,
        device: Double,
        isReported: Bool = true,
        renderer: Double? = nil,
        tiler: Double? = nil,
        memoryInUse: UInt64
    ) {
        self.name = name
        self.device = device
        self.isReported = isReported
        self.renderer = renderer
        self.tiler = tiler
        self.memoryInUse = memoryInUse
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        device = try values.decode(Double.self, forKey: .device)
        // Snapshots written before the flag existed always carried a value.
        isReported = try values.decodeIfPresent(Bool.self, forKey: .isReported) ?? true
        renderer = try values.decodeIfPresent(Double.self, forKey: .renderer)
        tiler = try values.decodeIfPresent(Double.self, forKey: .tiler)
        memoryInUse = try values.decode(UInt64.self, forKey: .memoryInUse)
    }

    /// Device utilization from 0 to 1, or nil when the GPU does not report it.
    public var utilization: Double? {
        isReported ? device : nil
    }
}

public enum GPUReader {
    public static func samples() -> [GPUSample] {
        IORegistry.properties(ofClass: "IOAccelerator").compactMap(parse)
    }

    /// Reads one `IOAccelerator` entry; the keys are the ones the graphics driver reports.
    public static func parse(_ properties: [String: Any]) -> GPUSample? {
        guard let statistics = properties["PerformanceStatistics"] as? [String: Any] else { return nil }
        func share(_ key: String) -> Double? {
            (statistics[key] as? NSNumber).map { $0.doubleValue / 100 }
        }
        let device = share("Device Utilization %")
        return GPUSample(
            name: properties["model"] as? String ?? "GPU",
            device: device ?? 0,
            isReported: device != nil,
            renderer: share("Renderer Utilization %"),
            tiler: share("Tiler Utilization %"),
            memoryInUse: (statistics["In use system memory"] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
