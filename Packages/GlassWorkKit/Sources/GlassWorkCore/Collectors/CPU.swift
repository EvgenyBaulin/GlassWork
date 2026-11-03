import Darwin
import Foundation

/// Cumulative scheduler ticks of one logical core.
public struct CPUTicks: Sendable, Equatable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var total: UInt64 {
        user + system + idle + nice
    }
}

public struct CPUSample: Codable, Sendable, Equatable {
    /// All shares are 0...1.
    public var total: Double
    public var user: Double
    public var system: Double
    public var idle: Double
    public var cores: [Double]

    public init(total: Double, user: Double, system: Double, idle: Double, cores: [Double]) {
        self.total = total
        self.user = user
        self.system = system
        self.idle = idle
        self.cores = cores
    }

    /// Turns two tick snapshots into usage shares.
    public static func between(_ previous: [CPUTicks], _ current: [CPUTicks]) -> CPUSample? {
        guard previous.count == current.count, !current.isEmpty else { return nil }
        var user = 0.0
        var system = 0.0
        var idle = 0.0
        var cores: [Double] = []
        cores.reserveCapacity(current.count)
        for (old, new) in zip(previous, current) {
            let coreUser = Double(new.user &- old.user) + Double(new.nice &- old.nice)
            let coreSystem = Double(new.system &- old.system)
            let coreIdle = Double(new.idle &- old.idle)
            let sum = coreUser + coreSystem + coreIdle
            cores.append(sum > 0 ? (coreUser + coreSystem) / sum : 0)
            user += coreUser
            system += coreSystem
            idle += coreIdle
        }
        let sum = user + system + idle
        guard sum > 0 else { return nil }
        return CPUSample(
            total: (user + system) / sum,
            user: user / sum,
            system: system / sum,
            idle: idle / sum,
            cores: cores
        )
    }
}

public struct CPUInfo: Codable, Sendable, Equatable {
    public var brand: String
    public var performanceCores: Int
    public var efficiencyCores: Int

    public init(brand: String, performanceCores: Int, efficiencyCores: Int) {
        self.brand = brand
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
    }
}

public enum CPUReader {
    public static func ticks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            )
        }
        let stride = Int(CPU_STATE_MAX)
        return (0 ..< Int(count)).map { core in
            let base = core * stride
            return CPUTicks(
                user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            )
        }
    }

    public static func info() -> CPUInfo {
        CPUInfo(
            brand: Sysctl.string("machdep.cpu.brand_string") ?? "Mac",
            performanceCores: Sysctl.int("hw.perflevel0.logicalcpu") ?? Sysctl.int("hw.logicalcpu") ?? 0,
            efficiencyCores: Sysctl.int("hw.perflevel1.logicalcpu") ?? 0
        )
    }

    public static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : []
    }
}

/// Typed helpers over `sysctlbyname`.
enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
