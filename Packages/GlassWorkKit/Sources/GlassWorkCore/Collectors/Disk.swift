import DiskArbitration
import Foundation

public struct DiskVolume: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        path
    }

    public var name: String
    public var path: String
    public var total: UInt64
    public var free: UInt64
    public var isInternal: Bool
    public var isEjectable: Bool
    /// Optional, so a widget snapshot written before these existed still reads.
    public var isDiskImage: Bool?
    public var isNetwork: Bool?

    public var freeShare: Double {
        total > 0 ? Double(free) / Double(total) : 0
    }
}

public struct DiskCounters: Sendable, Equatable {
    public var read: UInt64
    public var written: UInt64

    public init(read: UInt64, written: UInt64) {
        self.read = read
        self.written = written
    }
}

public struct DiskActivity: Codable, Sendable, Equatable {
    /// Bytes per second.
    public var read: Double
    public var write: Double

    public static func between(
        _ previous: DiskCounters,
        _ current: DiskCounters,
        seconds: TimeInterval
    ) -> DiskActivity {
        let elapsed = max(seconds, 0.001)
        return DiskActivity(
            read: Double(current.read >= previous.read ? current.read - previous.read : 0) / elapsed,
            write: Double(current.written >= previous.written ? current.written - previous.written : 0) / elapsed
        )
    }
}

public enum DiskReader {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsBrowsableKey, .volumeIsLocalKey,
    ]

    /// Mounted volumes, the startup disk first. Free space is counted the way Finder counts it.
    public static func volumes() -> [DiskVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap(volume).sorted { lhs, rhs in
            if (lhs.path == "/") != (rhs.path == "/") {
                return lhs.path == "/"
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func volume(at url: URL) -> DiskVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.volumeIsBrowsable == true,
              let total = values.volumeTotalCapacity
        else { return nil }
        return DiskVolume(
            name: values.volumeName ?? url.lastPathComponent,
            path: url.path(percentEncoded: false),
            total: UInt64(total),
            free: UInt64(max(values.volumeAvailableCapacityForImportantUsage ?? 0, 0)),
            isInternal: values.volumeIsInternal ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isDiskImage: values.volumeIsEjectable == true ? isDiskImage(url) : false,
            isNetwork: values.volumeIsLocal == false
        )
    }

    /// Only the disk's description is read, nothing on the volume itself.
    private static func isDiskImage(_ url: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any]
        else { return false }
        return description[kDADiskDescriptionDeviceModelKey as String] as? String == "Disk Image"
    }

    public static func counters() -> DiskCounters {
        var total = DiskCounters(read: 0, written: 0)
        for properties in IORegistry.properties(ofClass: "IOBlockStorageDriver") {
            guard let statistics = properties["Statistics"] as? [String: Any] else { continue }
            total.read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            total.written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return total
    }
}
