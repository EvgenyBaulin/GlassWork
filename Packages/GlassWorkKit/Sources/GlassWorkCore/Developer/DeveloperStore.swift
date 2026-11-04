import Foundation
import Observation

/// Latest readings of the developer modules.
///
/// Each module has its own pace, set here, and reads off the main thread. Nothing is read unless
/// `tick` asks for it, so the store pauses with `SystemMonitor`.
@MainActor
@Observable
public final class DeveloperStore {
    public private(set) var ping = PingLog()

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
        default: 30
        }
    }

    private func read(_ module: ModuleID, at date: Date) {
        switch module {
        case .ping: readPing(at: date)
        default: break
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
