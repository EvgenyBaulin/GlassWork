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
    public var developer: Set<ModuleID> = []
    public var devices = false
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

    public init(
        weather: WeatherStore = WeatherStore(),
        rates: RatesStore = RatesStore(),
        clipboard: ClipboardStore = ClipboardStore(),
        nowPlaying: NowPlayingStore = NowPlayingStore()
    ) {
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

    /// Everything widgets show, read fresh regardless of the current demand.
    public func widgetSnapshot() async -> WidgetSnapshot {
        var full = MonitorDemand()
        full.cpu = true
        full.memory = true
        full.network = true
        full.disk = true
        full.battery = true
        full.gpu = true
        full.sensors = true
        full.processes = true
        let date = Date()
        await apply(sampler.read(full, includeSlow: true), at: date)
        var snapshot = WidgetSnapshot(date: date)
        snapshot.cpu = cpu
        snapshot.cpuInfo = cpuInfo
        snapshot.memory = memory
        snapshot.gpu = gpus.first
        snapshot.battery = battery
        snapshot.volumes = volumes
        snapshot.network = network
        snapshot.sensors = sensors
        snapshot.processes = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(12))
        snapshot.everyday = everyday.data
        snapshot.events = agenda.events
        snapshot.todos = agenda.todos
        snapshot.bootTime = SystemClock.bootTime()
        snapshot.screenTime = activity.screenTime
        snapshot.commandResults = activity.commandResults
        snapshot.endpointChecks = activity.endpointChecks
        snapshot.reviews = activity.reviews
        snapshot.runs = activity.runs
        snapshot.contributions = activity.contributions
        snapshot.place = weather.places.first
        snapshot.words = wordOfDay.recent(6, at: date)
        snapshot.nowPlaying = nowPlaying.widgetData
        return snapshot
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
        weather.tick(at: now)
        rates.tick(at: now)
        clipboard.tick(at: now)
        nowPlaying.tick(wanted: demand.nowPlaying, at: now)
        onUpdate?()
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
        if demand.processes {
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
