import Darwin
import Foundation

public enum MemoryPressure: String, Codable, Sendable {
    case normal, warning, critical

    public init(level: Int) {
        switch level {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}

public struct MemorySample: Codable, Sendable, Equatable {
    public var total: UInt64
    public var app: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cached: UInt64
    public var free: UInt64
    public var swapUsed: UInt64
    public var swapTotal: UInt64
    public var pressure: MemoryPressure

    /// Memory Used as Activity Monitor counts it.
    public var used: UInt64 {
        app + wired + compressed
    }

    public var usedShare: Double {
        total > 0 ? Double(used) / Double(total) : 0
    }
}

/// Raw page counters from the kernel.
public struct VMCounters: Sendable, Equatable {
    public var pageSize: UInt64
    public var free: UInt64
    public var wired: UInt64
    public var compressor: UInt64
    public var purgeable: UInt64
    public var external: UInt64
    public var `internal`: UInt64

    public init(
        pageSize: UInt64, free: UInt64, wired: UInt64, compressor: UInt64,
        purgeable: UInt64, external: UInt64, internal: UInt64
    ) {
        self.pageSize = pageSize
        self.free = free
        self.wired = wired
        self.compressor = compressor
        self.purgeable = purgeable
        self.external = external
        self.internal = `internal`
    }

    public func sample(total: UInt64, swapUsed: UInt64, swapTotal: UInt64, pressure: MemoryPressure) -> MemorySample {
        MemorySample(
            total: total,
            app: (`internal` > purgeable ? `internal` - purgeable : 0) * pageSize,
            wired: wired * pageSize,
            compressed: compressor * pageSize,
            cached: (external + purgeable) * pageSize,
            free: free * pageSize,
            swapUsed: swapUsed,
            swapTotal: swapTotal,
            pressure: pressure
        )
    }
}

public enum MemoryReader {
    public static func sample() -> MemorySample? {
        guard let counters = counters() else { return nil }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        let level = Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1
        return counters.sample(
            total: ProcessInfo.processInfo.physicalMemory,
            swapUsed: swap.xsu_used,
            swapTotal: swap.xsu_total,
            pressure: MemoryPressure(level: level)
        )
    }

    private static func counters() -> VMCounters? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return VMCounters(
            pageSize: UInt64(getpagesize()),
            free: UInt64(stats.free_count),
            wired: UInt64(stats.wire_count),
            compressor: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            external: UInt64(stats.external_page_count),
            internal: UInt64(stats.internal_page_count)
        )
    }
}
