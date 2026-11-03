import Foundation

public struct GPUSample: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        name
    }

    public var name: String
    public var device: Double
    public var renderer: Double
    public var tiler: Double
    public var memoryInUse: UInt64
}

public enum GPUReader {
    public static func samples() -> [GPUSample] {
        IORegistry.properties(ofClass: "IOAccelerator").compactMap(parse)
    }

    /// Reads one `IOAccelerator` entry; the keys are the ones the graphics driver reports.
    public static func parse(_ properties: [String: Any]) -> GPUSample? {
        guard let statistics = properties["PerformanceStatistics"] as? [String: Any] else { return nil }
        func share(_ key: String) -> Double {
            ((statistics[key] as? NSNumber)?.doubleValue ?? 0) / 100
        }
        return GPUSample(
            name: properties["model"] as? String ?? "GPU",
            device: share("Device Utilization %"),
            renderer: share("Renderer Utilization %"),
            tiler: share("Tiler Utilization %"),
            memoryInUse: (statistics["In use system memory"] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
