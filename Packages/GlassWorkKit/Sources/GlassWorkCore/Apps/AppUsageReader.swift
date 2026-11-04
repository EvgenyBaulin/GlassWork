import Darwin
import Foundation

/// The system's process list. Tests substitute their own.
public protocol ProcessTable: Sendable {
    func pids() -> [Int32]
    /// Nil for a process that is gone or belongs to another user.
    func counters(of pid: Int32) -> ProcessCounters?
    func facts(of pid: Int32) -> ProcessFacts
}

/// Clock ticks of this Mac, which `proc_pid_rusage` reports CPU time in on Apple silicon.
public struct Timebase: Sendable, Equatable {
    public var numerator: UInt32
    public var denominator: UInt32

    public init(numerator: UInt32, denominator: UInt32) {
        self.numerator = numerator
        self.denominator = denominator
    }

    public static let system: Timebase = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numerator: info.numer, denominator: max(info.denom, 1))
    }()

    public func nanoseconds(_ ticks: UInt64) -> UInt64 {
        UInt64(Double(ticks) * Double(numerator) / Double(denominator))
    }
}

/// Reads processes straight from the kernel. Unlike `ps`, this starts nothing, and it can read only this user's
/// processes, which is where all apps run.
public struct KernelProcessTable: ProcessTable {
    private typealias ResponsibleForPID = @convention(c) (pid_t) -> pid_t

    private let timebase: Timebase
    /// The one call that links a WebKit service to Safari. It is not public, so its absence must not matter: without
    /// it, bundles and parents still place most helpers.
    private let responsible: ResponsibleForPID?

    public init(timebase: Timebase = .system) {
        self.timebase = timebase
        let everywhere = UnsafeMutableRawPointer(bitPattern: -2)
        responsible = dlsym(everywhere, "responsibility_get_pid_responsible_for_pid")
            .map { unsafeBitCast($0, to: ResponsibleForPID.self) }
    }

    public func pids() -> [Int32] {
        let expected = proc_listallpids(nil, 0)
        guard expected > 0 else { return [] }
        // Room for what starts between the two calls.
        var list = [pid_t](repeating: 0, count: Int(expected) + 64)
        let count = list.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(list.prefix(Int(max(count, 0))))
    }

    public func counters(of pid: Int32) -> ProcessCounters? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return ProcessCounters(
            pid: pid,
            start: usage.ri_proc_start_abstime,
            cpuNanoseconds: timebase.nanoseconds(usage.ri_user_time + usage.ri_system_time),
            memory: usage.ri_phys_footprint
        )
    }

    public func facts(of pid: Int32) -> ProcessFacts {
        ProcessFacts(pid: pid, parent: parent(of: pid), responsible: responsible?(pid) ?? pid, path: Self.path(of: pid))
    }

    private func parent(of pid: Int32) -> Int32 {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return 0 }
        return Int32(info.pbi_ppid)
    }

    /// The executable of a process.
    public static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}

/// One read of every app.
public struct AppUsageReading: Sendable, Equatable {
    public var apps: [AppUsage]
    /// False on the first read and after a long gap, when CPU could not be worked out.
    public var hasCPU: Bool

    public init(apps: [AppUsage], hasCPU: Bool) {
        self.apps = apps
        self.hasCPU = hasCPU
    }
}

/// Keeps counters between reads, and what never changes per process, so a read costs one call per process.
public actor AppUsageReader {
    private let table: any ProcessTable
    private var facts: [Int32: ProcessFacts] = [:]
    private var owners: [Int32: String] = [:]
    private var ownersApps: [RunningAppInfo] = []
    private var previous: [Int32: ProcessCounters] = [:]
    private var previousDate: Date?

    /// Past this the Mac has probably slept, and an average over the gap would mean nothing.
    public static let longestGap: TimeInterval = 180

    public init(table: any ProcessTable = KernelProcessTable()) {
        self.table = table
    }

    public func read(_ apps: [RunningAppInfo], at date: Date) -> AppUsageReading {
        let counters = table.pids().compactMap(table.counters)
        updateOwners(counters, apps: apps)
        let seconds = previousDate.map { date.timeIntervalSince($0) }
            .flatMap { (0 ... Self.longestGap).contains($0) ? $0 : nil }
        let usage = AppUsageGrouping.usage(
            apps: apps,
            counters: counters,
            previous: previous,
            seconds: seconds,
            owners: owners
        )
        previous = Dictionary(counters.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
        previousDate = date
        return AppUsageReading(apps: usage, hasCPU: seconds != nil)
    }

    /// Only processes that are new since the last read are looked at, unless the apps themselves changed.
    private func updateOwners(_ counters: [ProcessCounters], apps: [RunningAppInfo]) {
        var current: [Int32: ProcessFacts] = [:]
        current.reserveCapacity(counters.count)
        var fresh: [Int32] = []
        for process in counters {
            if let known = facts[process.pid], previous[process.pid]?.start == process.start {
                current[process.pid] = known
            } else {
                current[process.pid] = table.facts(of: process.pid)
                fresh.append(process.pid)
            }
        }
        facts = current
        if apps == ownersApps {
            owners = owners.filter { current[$0.key] != nil }
            fresh.forEach { owners[$0] = nil }
            owners.merge(AppUsageGrouping.owners(of: fresh, facts: current, apps: apps)) { _, new in new }
        } else {
            owners = AppUsageGrouping.owners(of: current.keys, facts: current, apps: apps)
            ownersApps = apps
        }
    }
}
