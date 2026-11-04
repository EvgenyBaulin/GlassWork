import Foundation
import Observation

/// Latest readings of the developer modules.
///
/// Each module has its own pace, set here, and reads off the main thread. Nothing is read unless
/// `tick` asks for it, so the store pauses with `SystemMonitor`.
@MainActor
@Observable
public final class DeveloperStore {
    public private(set) var devServers: DevServerReading?
    public private(set) var docker: DockerReading?
    public private(set) var ping = PingLog()
    public private(set) var vpn: VPNReading?
    /// When the connection was first seen, which is close enough to when it started.
    public private(set) var vpnSince: Date?
    public private(set) var wifi: WiFiReading?
    /// The last minute of signal, on `WiFiSignal`'s scale.
    public private(set) var wifiSignal = History<Double>(capacity: 13)

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
    @ObservationIgnored private var lastRead: [ModuleID: Date] = [:]
    @ObservationIgnored private var reading: Set<ModuleID> = []

    public init(runner: ProcessRunning = ProcessRunner()) {
        self.runner = runner
    }

    /// Reads every module in `demand` that is due.
    public func tick(at date: Date = Date(), demand: Set<ModuleID>) {
        for module in demand where isDue(module, at: date) {
            lastRead[module] = date
            read(module, at: date)
        }
    }

    private func isDue(_ module: ModuleID, at date: Date) -> Bool {
        guard !reading.contains(module) else { return false }
        guard let last = lastRead[module] else { return true }
        return date.timeIntervalSince(last) >= interval(of: module)
    }

    private func interval(of module: ModuleID) -> TimeInterval {
        switch module {
        case .wifi: 5
        case .vpn: 10
        default: 30
        }
    }

    private func read(_ module: ModuleID, at date: Date) {
        switch module {
        case .devServers: readDevServers()
        case .docker: readDocker()
        case .ping: readPing(at: date)
        case .vpn: readVPN(at: date)
        case .wifi: readWiFi(at: date)
        default: break
        }
    }

    private func readDevServers() {
        let collector = DevServerCollector(runner: runner)
        load(.devServers) {
            await collector.read()
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
    }
}
