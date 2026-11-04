import Foundation
import Observation

public enum Metric: String, CaseIterable, Sendable {
    case cpu, memory, download, upload, diskRead, diskWrite, gpu, temperature, fan
}

/// What the current UI needs. Anything not requested is not read at all.
public struct MonitorDemand: Sendable, Equatable {
    public var cpu = false
    public var memory = false
    public var network = false
    public var disk = false
    public var battery = false
    public var gpu = false
    public var sensors = false
    public var processes = false
    /// The process list on the slow pace: `ps` every two seconds is too much for a widget.
    public var slowProcesses = false
    /// A list of apps is on screen. Without it apps are still read, slowly, for their history.
    public var liveApps = false
    public var developer: Set<ModuleID> = []
    public var devices = false
    public var timeMachine = false
    public var nowPlaying = false

    public init() {}
}

/// Latest readings and in-memory history of every system metric.
@MainActor
@Observable
public final class SystemMonitor {
    public private(set) var cpuInfo = CPUReader.info()
    public private(set) var cpu: CPUSample?
    public private(set) var loadAverage: [Double] = []
    public private(set) var memory: MemorySample?
    public private(set) var network: NetworkSample?
    public private(set) var diskActivity: DiskActivity?
    public private(set) var volumes: [DiskVolume] = []
    public private(set) var battery: BatterySample?
    public private(set) var gpus: [GPUSample] = []
    public private(set) var sensors: SensorSample?
    public private(set) var processes: [ProcessUsage] = []
    public private(set) var deviceBatteries: [DeviceBattery] = []
    public private(set) var timeMachine: TimeMachineStatus?
    public private(set) var histories: [Metric: TieredHistory] = [:]
    public private(set) var fanHistories: [Int: TieredHistory] = [:]

    /// What the temperature graph records. Changing it starts the graph afresh.
    public var temperatureSource = SensorChoice.averageCPU {
        didSet {
            if temperatureSource != oldValue {
                histories[.temperature] = nil
            }
        }
    }

    /// Timers, notes and other small modules, ticking along with the monitor.
    public let everyday = EverydayStore()
    /// Git, Docker, Ping and the other developer modules, each at its own pace.
    public let developer = DeveloperStore()
    /// Calendar events and reminders.
    public let agenda = AgendaStore()
    /// Screen time, commands, endpoints and GitHub.
    public let activity = ActivityStore()
    /// What each app uses, and its history.
    public let apps: AppUsageStore
    /// Looks words up in the system dictionary for the Word of the Day widget.
    public let wordOfDay = WordOfDayProvider()
    /// These only reach the network or the disk once the app asks them to.
    public let weather: WeatherStore
    public let rates: RatesStore
    public let clipboard: ClipboardStore
    /// The adapter process runs only while `demand.nowPlaying` is set.
    public let nowPlaying: NowPlayingStore

    public var demand = MonitorDemand()
    public var interval: TimeInterval = 2
    public var slowInterval: TimeInterval = 30

    /// Called after each read. Menu bar items redraw from here, without SwiftUI's update machinery.
    @ObservationIgnored public var onUpdate: (() -> Void)?

    @ObservationIgnored private let sampler = Sampler()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastSlow = Date.distantPast
    @ObservationIgnored private var lastDevices = Date.distantPast
    @ObservationIgnored private var lastTimeMachine = Date.distantPast
    /// An empty list before the first answer would read as "no devices".
    @ObservationIgnored private var hasReadDevices = false

    /// `system_profiler` takes seconds and batteries drain slowly, and backups run hourly at most.
    private static let occasionalInterval: TimeInterval = 300

    public init(
        weather: WeatherStore = WeatherStore(),
        rates: RatesStore = RatesStore(),
        clipboard: ClipboardStore = ClipboardStore(),
        nowPlaying: NowPlayingStore = NowPlayingStore(),
        apps: AppUsageStore = AppUsageStore()
    ) {
        self.apps = apps
        self.weather = weather
        self.rates = rates
        self.clipboard = clipboard
        self.nowPlaying = nowPlaying
        developer.onChange = { [weak self] in self?.onUpdate?() }
        nowPlaying.onUpdate = { [weak self] in self?.onUpdate?() }
    }

    public var isRunning: Bool {
        loop != nil
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await tick()
                try? await Task.sleep(for: .seconds(effectiveInterval))
            }
        }
    }

    /// Nothing is read while the Mac sleeps or the screen is locked.
    public func stop() {
        loop?.cancel()
        loop = nil
        nowPlaying.stop()
    }

    /// One read of what `kinds` want and the regular tick does not cover.
    ///
    /// This serves system widgets, which refresh once a minute: sampling them on every tick would cost far more.
    public func readForWidgets(_ kinds: Set<WidgetKind>) async {
        let extra = MonitorDemand(widgets: kinds).subtracting(demand)
        guard isRunning, extra.readsSamples else { return }
        await apply(sampler.read(extra, includeSlow: true), at: Date())
    }

    /// What `kinds` show, from the latest readings. Nothing is read here, so calling it often costs little.
    public func widgetSnapshot(for kinds: Set<WidgetKind>, at date: Date = Date()) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: date)
        snapshot.cpu = cpu
        snapshot.cpuInfo = cpuInfo
        snapshot.memory = memory
        snapshot.gpu = gpus.first
        snapshot.battery = battery
        snapshot.volumes = volumes
        snapshot.network = network
        snapshot.sensors = sensors
        if !kinds.isDisjoint(with: [.activity, .topApps]) {
            snapshot.processes = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(12))
            snapshot.apps = apps.apps.sorted(by: .cpu).prefix(12).map {
                ProcessUsage(pid: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory)
            }
        }
        snapshot.everyday = everyday.data
        snapshot.events = agenda.events
        snapshot.todos = agenda.todos
        snapshot.bootTime = SystemClock.bootTime()
        if !kinds.isDisjoint(with: WidgetKind.screenTimeKinds) {
            snapshot.screenTime = activity.screenTime
        }
        snapshot.commandResults = activity.commandResults
        snapshot.endpointChecks = activity.endpointChecks
        snapshot.reviews = activity.reviews
        snapshot.runs = activity.runs
        snapshot.contributions = activity.contributions
        snapshot.place = weather.places.first
        if kinds.contains(.wordOfDay) {
            snapshot.words = wordOfDay.recent(6, at: date)
        }
        if !kinds.isDisjoint(with: [.nowPlaying, .lyrics]) {
            snapshot.nowPlaying = nowPlaying.widgetData
        }
        fillDetails(of: &snapshot, for: kinds, at: date)
        return snapshot
    }

    private func fillDetails(of snapshot: inout WidgetSnapshot, for kinds: Set<WidgetKind>, at date: Date) {
        if kinds.contains(.fans) {
            let since = date.addingTimeInterval(-600)
            snapshot.fanHistory = fanHistories.mapValues { history in
                history.points(in: .hour, now: date).filter { $0.date >= since }
            }
        }
        if kinds.contains(.diskActivity) {
            snapshot.diskActivity = diskActivity
            snapshot.diskMinute = diskHistory(.minute, seconds: 60, at: date)
            snapshot.diskLonger = diskHistory(.hour, seconds: 300, at: date)
        }
        if kinds.contains(.weather) {
            snapshot.weather = WidgetWeather(
                reports: weather.reports,
                isStale: weather.isStale,
                hasPlaces: !weather.places.isEmpty
            )
        }
        if kinds.contains(.rates) {
            snapshot.rates = WidgetRates(
                quotes: rates.snapshot.quotes,
                updatedAt: rates.snapshot.updatedAt,
                isStale: rates.isStale
            )
        }
        fillDeveloper(of: &snapshot, for: kinds, at: date)
        if kinds.contains(.devices) {
            snapshot.devices = hasReadDevices ? deviceBatteries : nil
        }
        if kinds.contains(.timeMachine) {
            snapshot.timeMachine = timeMachine
        }
    }

    private func fillDeveloper(of snapshot: inout WidgetSnapshot, for kinds: Set<WidgetKind>, at date: Date) {
        if kinds.contains(.git) {
            snapshot.git = developer.git
        }
        if kinds.contains(.devServers) {
            snapshot.devServers = developer.devServers
        }
        if kinds.contains(.containers) {
            snapshot.docker = developer.docker
        }
        if kinds.contains(.aiUsage) {
            snapshot.aiUsage = developer.aiUsage
        }
        if kinds.contains(.wifiSignal) {
            snapshot.wifi = developer.wifi
            snapshot.wifiHistory = developer.wifiSignal.points(since: date.addingTimeInterval(-600))
        }
    }

    private func diskHistory(_ range: TieredHistory.Range, seconds: TimeInterval, at date: Date) -> WidgetDiskHistory {
        let since = date.addingTimeInterval(-seconds)
        func points(_ metric: Metric) -> [History<Double>.Point] {
            (histories[metric]?.points(in: range, now: date) ?? []).filter { $0.date >= since }
        }
        return WidgetDiskHistory(read: points(.diskRead), write: points(.diskWrite))
    }

    /// Reads right away, for example when a panel opens.
    public func refresh() {
        Task { await tick() }
    }

    public func points(_ metric: Metric, in range: TieredHistory.Range) -> [History<Double>.Point] {
        histories[metric]?.points(in: range) ?? []
    }

    public func fanPoints(_ fan: Int, in range: TieredHistory.Range) -> [History<Double>.Point] {
        fanHistories[fan]?.points(in: range) ?? []
    }

    /// Battery power halves the polling rate and Low Power Mode quarters it.
    private var effectiveInterval: TimeInterval {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return interval * 4
        }
        return battery?.isOnAC == false ? interval * 2 : interval
    }

    private func tick() async {
        let now = Date()
        let includeSlow = now.timeIntervalSince(lastSlow) >= slowInterval
        if includeSlow {
            lastSlow = now
        }
        let reading = await sampler.read(demand, includeSlow: includeSlow)
        apply(reading, at: now)
        everyday.tick(at: now)
        developer.tick(at: now, demand: demand.developer)
        apps.tick(at: now, isLive: demand.liveApps)
        weather.tick(at: now)
        rates.tick(at: now)
        clipboard.tick(at: now)
        nowPlaying.tick(wanted: demand.nowPlaying, at: now)
        readOccasional(at: now)
        onUpdate?()
    }

    private func readOccasional(at date: Date) {
        if demand.devices, date.timeIntervalSince(lastDevices) >= Self.occasionalInterval {
            lastDevices = date
            Task {
                deviceBatteries = await DeviceBatteryReader.read()
                hasReadDevices = true
            }
        }
        if demand.timeMachine, date.timeIntervalSince(lastTimeMachine) >= Self.occasionalInterval {
            lastTimeMachine = date
            Task { timeMachine = await TimeMachineReader.read() }
        }
    }

    private func apply(_ reading: Sampler.Reading, at date: Date) {
        applyCompute(reading, at: date)
        applyStorage(reading, at: date)
        if let value = reading.battery {
            battery = value
        }
        if let value = reading.processes {
            processes = value
        }
    }

    private func applyCompute(_ reading: Sampler.Reading, at date: Date) {
        if let value = reading.cpu {
            cpu = value
            record(.cpu, value.total, date)
        }
        if !reading.loadAverage.isEmpty {
            loadAverage = reading.loadAverage
        }
        if let value = reading.memory {
            memory = value
            record(.memory, value.usedShare, date)
        }
        if let value = reading.gpus {
            gpus = value
            if let first = value.first {
                record(.gpu, first.device, date)
            }
        }
        if let value = reading.sensors {
            sensors = value
            if let celsius = value.celsius(for: temperatureSource) {
                record(.temperature, celsius, date)
            }
            if let rpm = value.averageFanRPM {
                record(.fan, rpm, date)
            }
            for fan in value.fans {
                fanHistories[fan.id, default: TieredHistory()].append(fan.rpm, at: date)
            }
        }
    }

    private func applyStorage(_ reading: Sampler.Reading, at date: Date) {
        if let value = reading.network {
            network = value
            record(.download, value.download, date)
            record(.upload, value.upload, date)
        }
        if let value = reading.diskActivity {
            diskActivity = value
            record(.diskRead, value.read, date)
            record(.diskWrite, value.write, date)
        }
        if let value = reading.volumes {
            volumes = value
        }
    }

    private func record(_ metric: Metric, _ value: Double, _ date: Date) {
        histories[metric, default: TieredHistory()].append(value, at: date)
    }
}

/// Holds counters between reads and keeps all system calls off the main thread.
actor Sampler {
    struct Reading: Sendable {
        var cpu: CPUSample?
        var loadAverage: [Double] = []
        var memory: MemorySample?
        var network: NetworkSample?
        var diskActivity: DiskActivity?
        var volumes: [DiskVolume]?
        var battery: BatterySample?
        var gpus: [GPUSample]?
        var sensors: SensorSample?
        var processes: [ProcessUsage]?
        var devices: [DeviceBattery]?
    }

    private var ticks: [CPUTicks] = []
    private var interfaces: [InterfaceCounters] = []
    private var interfacesDate = Date()
    private var sessionReceived: UInt64 = 0
    private var sessionSent: UInt64 = 0
    private var disk: DiskCounters?
    private var diskDate = Date()
    private lazy var sensorReader = SensorReader()
    private var sensorTick = 0

    func read(_ demand: MonitorDemand, includeSlow: Bool) async -> Reading {
        var reading = Reading()
        if demand.cpu {
            readCPU(into: &reading)
        }
        if demand.memory {
            reading.memory = MemoryReader.sample()
        }
        if demand.network {
            reading.network = readNetwork()
        }
        if demand.disk {
            reading.diskActivity = readDisk()
        }
        if demand.gpu {
            reading.gpus = GPUReader.samples()
        }
        if demand.sensors {
            reading.sensors = sensorReader?.sample()
        }
        if demand.processes || (includeSlow && demand.slowProcesses) {
            reading.processes = await ProcessList.read()
        }
        if includeSlow {
            if demand.disk {
                reading.volumes = DiskReader.volumes()
            }
            if demand.battery {
                reading.battery = BatteryReader.sample()
            }
        }
        return reading
    }

    /// Temperatures move slowly: every third read is enough unless a panel shows them live.
    private func shouldReadSensors(detailed: Bool) -> Bool {
        sensorTick += 1
        return detailed || sensorTick % 3 == 1
    }

    private func readCPU(into reading: inout Reading) {
        let current = CPUReader.ticks()
        reading.cpu = CPUSample.between(ticks, current)
        reading.loadAverage = CPUReader.loadAverage()
        ticks = current
    }

    private func readNetwork() -> NetworkSample? {
        let current = NetworkReader.counters()
        let now = Date()
        defer {
            interfaces = current
            interfacesDate = now
        }
        guard !interfaces.isEmpty else { return nil }
        let sample = NetworkSample.between(
            interfaces,
            current,
            seconds: now.timeIntervalSince(interfacesDate),
            sessionReceived: sessionReceived,
            sessionSent: sessionSent
        )
        sessionReceived = sample.sessionReceived
        sessionSent = sample.sessionSent
        return sample
    }

    private func readDisk() -> DiskActivity? {
        let current = DiskReader.counters()
        let now = Date()
        defer {
            disk = current
            diskDate = now
        }
        guard let disk else { return nil }
        return DiskActivity.between(disk, current, seconds: now.timeIntervalSince(diskDate))
    }
}
