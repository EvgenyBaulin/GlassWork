import Foundation
import Observation

/// Seconds that keep counting through sleep, unlike uptime, so a nap cannot look like a short pause.
public enum FanClock {
    private static let origin = ContinuousClock.now

    @Sendable public static func now() -> TimeInterval {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}

/// The app's end of the helper connection.
public protocol FanHelperClient: AnyObject, Sendable {
    /// True when the helper did it. False covers a refused command and a lost connection alike.
    func send(_ command: FanCommand) async -> Bool
    func heartbeat() async -> Bool
    func disconnect()
}

public enum FanHelperState: Sendable, Equatable {
    case notInstalled, needsApproval, installing, installed
    case failed(String)
}

/// Reads sensors for the fan loop, which must keep running when the monitor pauses for a locked screen.
public actor FanSensorSource {
    private lazy var reader = SensorReader()

    public init() {}

    public func sample() -> SensorSample? {
        reader?.sample()
    }
}

/// Installing and removing the helper. Nothing happens unless the user presses a button.
@MainActor
public protocol FanHelperInstalling: AnyObject {
    var state: FanHelperState { get }
    func install() throws
    func uninstall() async throws
    func openApproval()
    /// Nil when this build cannot talk to the helper, for example when it is unsigned.
    func connect(onLost: @escaping @Sendable () -> Void) -> FanHelperClient?
}

/// Runs the fan engine while a mode other than Auto is on, and tells the UI what is happening.
@MainActor
@Observable
public final class FanControlModel {
    /// Well inside the helper's 10 s watchdog. Sets the rate of the failsafe check too.
    public static let tick = 2.0

    public private(set) var mode = FanMode.auto
    public private(set) var notice: FanNotice?
    public private(set) var helperState = FanHelperState.notInstalled

    /// Called once when the failsafe switches to Max, with the temperature that caused it.
    @ObservationIgnored public var onFailsafe: ((Double) -> Void)?

    @ObservationIgnored private var engine = FanEngine()
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let installer: FanHelperInstalling?
    @ObservationIgnored private let readSensors: @Sendable () async -> SensorSample?
    @ObservationIgnored private let isOnAC: () -> Bool
    @ObservationIgnored private let now: () -> TimeInterval
    @ObservationIgnored private var client: FanHelperClient?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastSample: SensorSample?

    public init(
        store: SettingsStore,
        installer: FanHelperInstalling?,
        readSensors: @escaping @Sendable () async -> SensorSample?,
        isOnAC: @escaping () -> Bool,
        now: @escaping () -> TimeInterval = FanClock.now
    ) {
        self.store = store
        self.installer = installer
        self.readSensors = readSensors
        self.isOnAC = isOnAC
        self.now = now
        refreshHelperState()
    }

    /// Control needs the helper and the user's consent; everything else is read-only.
    public var canControl: Bool {
        helperState == .installed && store.settings.fans.isControlEnabled
    }

    public var isRunning: Bool {
        loop != nil
    }

    public var settings: FanSettings {
        store.settings.fans
    }

    public func updateSettings(_ change: (inout FanSettings) -> Void) {
        store.update { change(&$0.fans) }
    }

    /// Applies the saved launch mode. Auto, the default, leaves the fans alone.
    public func applyLaunchMode() {
        refreshHelperState()
        let launchMode = store.settings.fans.launchMode
        if launchMode != .auto {
            select(launchMode)
        }
    }

    public func refreshHelperState() {
        helperState = installer?.state ?? .notInstalled
    }

    public func select(_ newMode: FanMode) {
        guard canControl || newMode == .auto else { return }
        engine.select(newMode)
        publish()
        Task { await step() }
    }

    public func toggleMax() {
        guard canControl else { return }
        engine.toggleMax()
        publish()
        Task { await step() }
    }

    public func dismissNotice() {
        engine.dismissNotice()
        publish()
    }

    /// Turning control off hands the fans back but keeps the helper installed.
    public func setControlEnabled(_ isEnabled: Bool) {
        store.update { $0.fans.isControlEnabled = isEnabled }
        if !isEnabled {
            select(.auto)
        }
    }

    public func install() {
        do {
            try installer?.install()
            helperState = installer?.state ?? .notInstalled
            if helperState == .installed {
                store.update { $0.fans.isControlEnabled = true }
            }
        } catch {
            // macOS reports a registration waiting for approval as an error.
            refreshHelperState()
            if helperState != .needsApproval {
                helperState = .failed(error.localizedDescription)
            }
        }
    }

    public func openApproval() {
        installer?.openApproval()
    }

    public func uninstall() async {
        engine.select(.auto)
        publish()
        await step()
        do {
            try await installer?.uninstall()
            dropClient()
            store.update { $0.fans.isControlEnabled = false }
            refreshHelperState()
        } catch {
            helperState = .failed(error.localizedDescription)
        }
    }

    public func willSleep() async {
        let commands = engine.willSleep()
        publish()
        await deliver(commands)
        stopLoop()
    }

    public func didWake() {
        engine.didWake(at: now())
        publish()
        if engine.resumeTime != nil {
            startLoop()
        }
    }

    /// One pass of the engine. Public so tests can drive it without waiting for the timer.
    public func step() async {
        let sample = await readSensors()
        lastSample = sample
        let commands = engine.step(FanEngineInput(
            time: now(),
            sample: sample,
            isOnAC: isOnAC(),
            settings: store.settings.fans
        ))
        publish()
        await deliver(commands)
        if engine.isActive || engine.resumeTime != nil {
            startLoop()
            if client != nil, await client?.heartbeat() == false {
                helperWentAway()
            }
        } else {
            stopLoop()
        }
    }

    private func deliver(_ commands: [FanCommand]) async {
        guard !commands.isEmpty else { return }
        let connection = connectedClient()
        for command in commands where await connection?.send(command) != true {
            helperWentAway()
            return
        }
    }

    private func connectedClient() -> FanHelperClient? {
        if client == nil {
            client = installer?.connect { [weak self] in
                Task { @MainActor in self?.helperWentAway() }
            }
        }
        return client
    }

    /// The helper restores Auto on its own when the connection ends, so dropping it is enough.
    private func helperWentAway() {
        engine.helperLost()
        publish()
        dropClient()
        stopLoop()
    }

    private func dropClient() {
        client?.disconnect()
        client = nil
    }

    private func publish() {
        let oldNotice = notice
        mode = engine.mode
        notice = engine.notice
        if case let .failsafeMax(celsius, _) = notice, notice != oldNotice {
            onFailsafe?(celsius)
        }
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tick))
                guard !Task.isCancelled else { return }
                await self?.step()
            }
        }
    }

    private func stopLoop() {
        loop?.cancel()
        loop = nil
    }
}
