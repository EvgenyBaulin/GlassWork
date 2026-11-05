import Foundation
import Observation

/// Latest readings of the developer modules.
///
/// Each module has its own pace, set here, and reads off the main thread. Nothing is read unless
/// `tick` asks for it, so the store pauses with `SystemMonitor`.
@MainActor
@Observable
public final class DeveloperStore {
    public private(set) var aiUsage: AIUsageReading?
    public private(set) var git: GitReading?
    public private(set) var devServers: DevServerReading?
    public private(set) var docker: DockerReading?
    public private(set) var ping = PingLog()
    public private(set) var vpn: VPNReading?
    /// When the connection was first seen, which is close enough to when it started.
    public private(set) var vpnSince: Date?
    public private(set) var wifi: WiFiReading?
    /// The last ten minutes of signal, on `WiFiSignal`'s scale.
    public private(set) var wifiSignal = History<Double>(capacity: 120)

    /// What the menu bar and the panel draw: the last minute.
    public var wifiLastMinute: [History<Double>.Point] {
        Array(wifiSignal.points.suffix(13))
    }

    public var options = DeveloperOptions() {
        didSet {
            if options != oldValue {
                optionsChanged(from: oldValue)
            }
        }
    }

    /// Called after every new reading, so menu bar items redraw.
    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private let runner: ProcessRunning
    @ObservationIgnored private let home: String
    @ObservationIgnored private let locateGit: @Sendable () -> String?
    @ObservationIgnored private var lastRead: [ModuleID: Date] = [:]
    @ObservationIgnored private var reading: Set<ModuleID> = []
    @ObservationIgnored private let gitWatcher = GitWatcher()
    @ObservationIgnored private var changedRepositories: Set<String> = []
    @ObservationIgnored private var lastChangeRead = Date.distantPast

    /// Builds touch files for minutes on end; one `git status` per repository in this time is plenty.
    private static let gitChangeInterval: TimeInterval = 5

    public init(
        runner: ProcessRunning = ProcessRunner(),
        home: String = NSHomeDirectory(),
        locateGit: @escaping @Sendable () -> String? = { ToolLocator.git() }
    ) {
        self.runner = runner
        self.home = home
        self.locateGit = locateGit
    }

    /// Reads every module in `demand` that is due.
    public func tick(at date: Date = Date(), demand: Set<ModuleID>) {
        for module in demand where isDue(module, at: date) {
            lastRead[module] = date
            read(module, at: date)
        }
        if demand.contains(.git) {
            readChangedRepositories(at: date)
        } else {
            gitWatcher.stop()
        }
    }

    /// Reads a module now, for its refresh button.
    public func refresh(_ module: ModuleID, at date: Date = Date()) {
        guard !reading.contains(module) else { return }
        lastRead[module] = date
        read(module, at: date)
    }

    /// Paths FSEvents reported. They wait for the next tick, so nothing is read during sleep.
    func repositoriesChanged(_ paths: [String]) {
        let known = git?.repositories.map(\.path) ?? []
        changedRepositories.formUnion(GitChangeFilter.repositories(changed: paths, in: known))
    }

    func isIdle(_ module: ModuleID) -> Bool {
        !reading.contains(module)
    }

    private func isDue(_ module: ModuleID, at date: Date) -> Bool {
        guard !reading.contains(module) else { return false }
        guard let last = lastRead[module] else { return true }
        return date.timeIntervalSince(last) >= interval(of: module)
    }

    private func interval(of module: ModuleID) -> TimeInterval {
        switch module {
        case .aiUsage: TimeInterval(options.aiRefreshMinutes * 60)
        case .wifi: 5
        case .vpn: 10
        case .ping: TimeInterval(options.pingIntervalSeconds)
        case .devServers: TimeInterval(options.devServerSeconds)
        // FSEvents covers changes, so this pass only picks up new repositories.
        case .git: 300
        default: 30
        }
    }

    private func read(_ module: ModuleID, at date: Date) {
        switch module {
        case .aiUsage: readAIUsage(at: date)
        case .git: readGit()
        case .devServers: readDevServers()
        case .docker: readDocker()
        case .ping: readPing(at: date)
        case .vpn: readVPN(at: date)
        case .wifi: readWiFi(at: date)
        default: break
        }
    }

    private func readAIUsage(at date: Date) {
        let collector = AIUsageCollector(runner: runner, home: home)
        load(.aiUsage) {
            await collector.read(at: date)
        } apply: { store, value in
            store.aiUsage = value.warning(at: store.options.usageWarnShare)
        }
    }

    private func readGit() {
        let collector = GitCollector(runner: runner, home: home, locate: locateGit)
        let manual = options.gitRepositories
        let depth = options.gitAutoDiscover ? options.gitSearchDepth : 0
        load(.git) {
            await collector.read(manual: manual, discoveryDepth: depth)
        } apply: { store, value in
            store.git = value
            store.watchRepositories()
        }
    }

    private func readChangedRepositories(at date: Date) {
        guard !changedRepositories.isEmpty,
              !reading.contains(.git),
              date.timeIntervalSince(lastChangeRead) >= Self.gitChangeInterval
        else { return }
        lastChangeRead = date
        let changed = git?.repositories.filter { changedRepositories.contains($0.path) } ?? []
        changedRepositories = []
        let collector = GitCollector(runner: runner, home: home, locate: locateGit)
        load(.git) {
            await collector.refresh(changed)
        } apply: { store, fresh in
            store.git = store.git?.updating(fresh)
        }
    }

    private func watchRepositories() {
        // Only what could be read: FSEvents in a protected folder GlassWork may not open would also ask.
        let paths = git?.repositories.filter { $0.problem == nil }.map(\.path).sorted() ?? []
        gitWatcher.watch(paths) { [weak self] changed in
            Task { @MainActor in self?.repositoriesChanged(changed) }
        }
    }

    private func readDevServers() {
        let collector = DevServerCollector(runner: runner)
        let rule = options.devServerRule
        load(.devServers) {
            await collector.read().filtered(by: rule)
        } apply: { store, value in
            store.devServers = value
        }
    }

    private func readDocker() {
        let collector = DockerCollector(runner: runner)
        load(.docker) {
            await collector.read()
        } apply: { store, value in
            store.docker = value
        }
    }

    private func readPing(at date: Date) {
        let collector = PingCollector(runner: runner)
        let host = options.pingHost
        load(.ping) {
            await collector.read(host: host)
        } apply: { store, outcome in
            // A host changed mid-read would otherwise put the old host's reply on the new chart.
            if store.options.pingHost == host {
                store.ping.append(outcome, at: date)
            }
        }
    }

    private func readVPN(at date: Date) {
        load(.vpn) {
            VPNReader.read()
        } apply: { store, value in
            store.vpn = value
            store.vpnSince = value.isConnected ? store.vpnSince ?? date : nil
        }
    }

    private func readWiFi(at date: Date) {
        load(.wifi) {
            WiFiReader.read()
        } apply: { store, value in
            store.wifi = value
            if let link = value.link {
                store.wifiSignal.append(WiFiSignal.plotted(link.rssi), at: date)
            }
        }
    }

    private func load<Value: Sendable>(
        _ module: ModuleID,
        work: @escaping @Sendable () async -> Value,
        apply: @escaping @MainActor (DeveloperStore, Value) -> Void
    ) {
        reading.insert(module)
        Task { [weak self] in
            let value = await work()
            guard let self else { return }
            apply(self, value)
            reading.remove(module)
            onChange?()
        }
    }

    private func optionsChanged(from old: DeveloperOptions) {
        if options.pingHost != old.pingHost {
            ping = PingLog()
            lastRead[.ping] = nil
        }
        ping.follow(intervalSeconds: options.pingIntervalSeconds)
        aiUsage = aiUsage?.warning(at: options.usageWarnShare)
        if options.devServerRule != old.devServerRule {
            lastRead[.devServers] = nil
        }
        if options.gitRepositories != old.gitRepositories
            || options.gitAutoDiscover != old.gitAutoDiscover
            || options.gitSearchDepth != old.gitSearchDepth
        {
            lastRead[.git] = nil
        }
    }
}
