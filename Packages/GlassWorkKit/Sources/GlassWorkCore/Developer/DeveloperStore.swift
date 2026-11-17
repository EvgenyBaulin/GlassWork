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
    public private(set) var dockerContexts: [DockerContext] = []
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
    /// Modules with a read in flight. Observed, so panels can show that they are updating.
    private var reading: Set<ModuleID> = []
    @ObservationIgnored private let gitWatcher = GitWatcher()
    @ObservationIgnored private var changedRepositories: Set<String> = []
    @ObservationIgnored private var lastChangeRead = Date.distantPast
    @ObservationIgnored private var isLive = true
    @ObservationIgnored private var lastDemand: Set<ModuleID> = []
    @ObservationIgnored private var networkWatcher: NetworkPathWatcher?

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

    /// Reads every module in `demand` that is due. `live` is set while a panel shows the modules, which then read at
    /// their quicker pace.
    public func tick(at date: Date = Date(), demand: Set<ModuleID>, live: Bool = true) {
        isLive = live
        lastDemand = demand
        watchNetwork(demand.contains(.vpn) || demand.contains(.wifi))
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

    /// A VPN coming up or a Wi-Fi network changing shows at once instead of on the next slow read.
    private func watchNetwork(_ wanted: Bool) {
        guard wanted != (networkWatcher != nil) else { return }
        networkWatcher = wanted ? NetworkPathWatcher { [weak self] in self?.networkChanged() } : nil
    }

    func networkChanged(at date: Date = Date()) {
        for module in [ModuleID.vpn, .wifi] where lastDemand.contains(module) {
            refresh(module, at: date)
        }
    }

    /// Paths FSEvents reported. They wait for the next tick, so nothing is read during sleep.
    func repositoriesChanged(_ paths: [String]) {
        let known = git?.repositories.map(\.path) ?? []
        changedRepositories.formUnion(GitChangeFilter.repositories(changed: paths, in: known))
    }

    /// True while a read of the module is in flight.
    public func isUpdating(_ module: ModuleID) -> Bool {
        reading.contains(module)
    }

    func isIdle(_ module: ModuleID) -> Bool {
        !reading.contains(module)
    }

    private func isDue(_ module: ModuleID, at date: Date) -> Bool {
        guard !reading.contains(module) else { return false }
        guard let last = lastRead[module] else { return true }
        return date.timeIntervalSince(last) >= interval(of: module)
    }

    func interval(of module: ModuleID) -> TimeInterval {
        switch module {
        case .aiUsage: TimeInterval(options.aiRefreshMinutes * 60)
        // Owner's table (2026-11-16): slower while only the menu bar shows them; a change of network reads at once.
        case .wifi: isLive ? 5 : 10
        case .vpn: isLive ? 10 : 30
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
        let off = options.aiDisabledTools
        load(.aiUsage) {
            await collector.read(at: date, skipping: off)
        } apply: { store, value in
            // Settings may have changed during the read; the newest choice decides what is kept.
            store.aiUsage = value.keepingKnown(from: store.aiUsage)
                .excluding(store.options.aiDisabledTools)
                .warning(at: store.options.usageWarnShare)
        }
    }

    /// The reading saved before the app last quit, so a first read that finds nothing still has numbers to keep.
    public func restore(aiUsage saved: AIUsageReading?) {
        guard aiUsage == nil, let saved else { return }
        aiUsage = saved.excluding(options.aiDisabledTools).warning(at: options.usageWarnShare)
    }

    private func readGit() {
        let collector = GitCollector(runner: runner, home: home, locate: locateGit)
        let manual = options.gitRepositories + [options.gitWidgetRepository].compactMap(\.self)
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
        let collector = dockerCollector()
        load(.docker) {
            await (collector.read(), collector.contexts())
        } apply: { store, value in
            store.docker = value.0
            store.dockerContexts = value.1
        }
    }

    private func dockerCollector() -> DockerCollector {
        let custom = options.dockerPath
        return DockerCollector(runner: runner, locate: { DockerCLI.resolve(custom: custom) })
    }

    /// Switches the Docker context, then reads again so the panel shows its containers.
    public func useDockerContext(_ name: String) {
        let collector = dockerCollector()
        Task { [weak self] in
            guard await collector.use(context: name) else { return }
            self?.lastRead[.docker] = nil
            self?.refresh(.docker)
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
        aiUsage = aiUsage?.excluding(options.aiDisabledTools).warning(at: options.usageWarnShare)
        if options.aiDisabledTools != old.aiDisabledTools {
            lastRead[.aiUsage] = nil
        }
        if options.dockerPath != old.dockerPath {
            lastRead[.docker] = nil
        }
        if options.devServerRule != old.devServerRule {
            lastRead[.devServers] = nil
        }
        if options.gitRepositories != old.gitRepositories
            || options.gitWidgetRepository != old.gitWidgetRepository
            || options.gitAutoDiscover != old.gitAutoDiscover
            || options.gitSearchDepth != old.gitSearchDepth
        {
            lastRead[.git] = nil
        }
    }
}
