import Foundation

/// A running app as the workspace reports it.
public struct RunningAppInfo: Sendable, Equatable {
    public enum Role: Sendable {
        /// Has a Dock icon.
        case regular
        /// Lives in the menu bar.
        case accessory
        case background
    }

    public var pid: Int32
    public var name: String
    public var bundleID: String?
    /// The app bundle.
    public var path: String?
    public var role: Role

    public init(pid: Int32, name: String, bundleID: String?, path: String?, role: Role) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.role = role
    }

    /// Stays the same between launches, unlike the pid, and across moves of the bundle.
    public var id: String {
        bundleID ?? path ?? name
    }

    /// Menu bar apps count, except the ones macOS runs for itself such as Spotlight.
    public var isListed: Bool {
        switch role {
        case .regular: true
        case .accessory: path?.hasPrefix("/System/") == false
        case .background: false
        }
    }
}

/// One app with all its helpers added up.
public struct AppUsage: Identifiable, Sendable, Equatable {
    public var id: String
    public var pid: Int32
    public var name: String
    public var bundleID: String?
    public var path: String?
    /// Percent of one core, so a busy app can pass 100.
    public var cpu: Double
    /// Bytes: what Activity Monitor calls Memory. Pages shared between helpers are not counted twice.
    public var memory: UInt64
    public var helpers: Int

    public init(
        id: String,
        pid: Int32,
        name: String,
        bundleID: String? = nil,
        path: String? = nil,
        cpu: Double,
        memory: UInt64,
        helpers: Int = 0
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.path = path
        self.cpu = cpu
        self.memory = memory
        self.helpers = helpers
    }
}

public enum AppUsageSort: Sendable {
    case cpu, memory
}

public extension [AppUsage] {
    /// Heaviest first. The name settles ties, so equal apps do not swap places between reads.
    func sorted(by sort: AppUsageSort) -> [AppUsage] {
        sorted { first, second in
            let (left, right) = switch sort {
            case .cpu: (first.cpu, second.cpu)
            case .memory: (Double(first.memory), Double(second.memory))
            }
            if left != right {
                return left > right
            }
            return first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    /// Keeps `order`, for a list under the pointer: a row must not move while someone aims at its Quit button.
    /// Apps not in `order` go last.
    func arranged(following order: [AppUsage.ID]) -> [AppUsage] {
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return enumerated().sorted { first, second in
            let left = positions[first.element.id] ?? order.count + first.offset
            let right = positions[second.element.id] ?? order.count + second.offset
            return left < right
        }.map(\.element)
    }

    /// Names that start with `query` come before names that only contain it.
    func matching(_ query: String) -> [AppUsage] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return self }
        let hits = filter { $0.name.localizedCaseInsensitiveContains(text) }
        let starts = hits.filter { $0.name.lowercased().hasPrefix(text.lowercased()) }
        return starts + hits.filter { !starts.contains($0) }
    }
}

/// What does not change while a process lives.
public struct ProcessFacts: Sendable, Equatable {
    public var pid: Int32
    public var parent: Int32
    /// The process macOS holds responsible for this one: how a WebKit service leads back to Safari.
    public var responsible: Int32
    /// The executable.
    public var path: String?

    public init(pid: Int32, parent: Int32, responsible: Int32, path: String?) {
        self.pid = pid
        self.parent = parent
        self.responsible = responsible
        self.path = path
    }
}

/// Totals since a process started.
public struct ProcessCounters: Sendable, Equatable {
    public var pid: Int32
    /// Tells a process from a later one that got the same pid.
    public var start: UInt64
    public var cpuNanoseconds: UInt64
    public var memory: UInt64

    public init(pid: Int32, start: UInt64, cpuNanoseconds: UInt64, memory: UInt64) {
        self.pid = pid
        self.start = start
        self.cpuNanoseconds = cpuNanoseconds
        self.memory = memory
    }
}

/// Works out which app each process belongs to, and adds them up.
public enum AppUsageGrouping {
    /// A chain of parents is never this long, and a loop in stale data must end.
    private static let maxDepth = 32

    /// The owner of every process in `pids` that has one, as app ids by pid.
    ///
    /// A process belongs to an app when it is the app, when macOS holds the app responsible for it, when it sits
    /// inside the app's bundle, or when its parent belongs to one. A daemon with none of these is left out.
    public static func owners(
        of pids: some Sequence<Int32>,
        facts: [Int32: ProcessFacts],
        apps: [RunningAppInfo]
    ) -> [Int32: String] {
        let byPID = Dictionary(apps.map { ($0.pid, $0.id) }, uniquingKeysWith: { first, _ in first })
        let bundles = apps.compactMap { app in app.path.map { (path: bundlePrefix($0), id: app.id) } }
            .sorted { $0.path.count > $1.path.count }
        var owners: [Int32: String] = [:]
        for pid in pids {
            if let owner = owner(of: pid, facts, byPID, bundles) {
                owners[pid] = owner
            }
        }
        return owners
    }

    private static func owner(
        of pid: Int32,
        _ facts: [Int32: ProcessFacts],
        _ byPID: [Int32: String],
        _ bundles: [(path: String, id: String)]
    ) -> String? {
        var current = pid
        for _ in 0 ..< maxDepth {
            if let app = byPID[current] {
                return app
            }
            guard let fact = facts[current] else { return nil }
            if let app = byPID[fact.responsible] {
                return app
            }
            for path in [facts[fact.responsible]?.path, fact.path].compactMap(\.self) {
                if let app = bundles.first(where: { path.hasPrefix($0.path) }) {
                    return app.id
                }
            }
            guard fact.parent > 1, fact.parent != current else { return nil }
            current = fact.parent
        }
        return nil
    }

    /// With the slash, so `/Applications/Foo.app` does not take in `/Applications/Foo.app.old`.
    private static func bundlePrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// Adds up processes per app.
    ///
    /// - Parameter seconds: Time since `previous`. Without it there is nothing to compare, so CPU stays at zero.
    public static func usage(
        apps: [RunningAppInfo],
        counters: [ProcessCounters],
        previous: [Int32: ProcessCounters],
        seconds: TimeInterval?,
        owners: [Int32: String]
    ) -> [AppUsage] {
        var sums = Dictionary(uniqueKeysWithValues: apps.map { app in
            (app.id, AppUsage(
                id: app.id,
                pid: app.pid,
                name: app.name,
                bundleID: app.bundleID,
                path: app.path,
                cpu: 0,
                memory: 0,
                helpers: -1
            ))
        })
        for process in counters {
            guard let id = owners[process.pid], sums[id] != nil else { continue }
            sums[id]?.memory += process.memory
            sums[id]?.helpers += 1
            if let seconds, seconds > 0 {
                sums[id]?.cpu += cpuPercent(process, previous: previous[process.pid], seconds: seconds)
            }
        }
        return sums.values.filter { $0.helpers >= 0 }.sorted(by: .memory)
    }

    /// A process that started since the last read used all of its CPU time in between.
    private static func cpuPercent(
        _ process: ProcessCounters,
        previous: ProcessCounters?,
        seconds: TimeInterval
    ) -> Double {
        let base = previous?.start == process.start ? previous?.cpuNanoseconds ?? 0 : 0
        let used = process.cpuNanoseconds >= base ? process.cpuNanoseconds - base : 0
        return Double(used) / 1e9 / seconds * 100
    }
}
