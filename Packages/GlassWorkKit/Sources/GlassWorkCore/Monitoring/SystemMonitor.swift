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
    public var sensorDetail = SensorDetail.summary
    public var processes = false
    /// The process list on the slow pace: `ps` every two seconds is too much for a widget.
    public var slowProcesses = false
    /// A list of apps is on screen. Without it apps are still read, slowly, for their history.
    public var liveApps = false
    public var developer: Set<ModuleID> = []
    /// A panel or the main window is open: developer modules read at the pace a panel shows, not the menu bar's.
    public var developerLive = false
    public var devices = false
    public var timeMachine = false
    public var nowPlaying = false
    /// Metrics that only the menu bar shows read at their own pace, in seconds. A metric missing here reads on
    /// every tick: widgets with charts, the main window, Settings and open panels never set one.
    public var paces: [SampleKind: TimeInterval] = [:]

    public init() {}
}

/// Metrics that can read slower than the loop.
public enum SampleKind: Hashable, Sendable, CaseIterable {
    case cpu, memory, gpu, diskActivity, sensors

    /// Owner's table (2026-11-16) for a module shown only in the menu bar.
    public static func menuBarPaces(for modules: Set<ModuleID>) -> [SampleKind: TimeInterval] {
        var paces: [SampleKind: TimeInterval] = [:]
        if !modules.contains(.cpu) {
            paces[.cpu] = 5
        }
        paces[.memory] = modules.contains(.overview) ? 5 : 10
        paces[.gpu] = 5
        paces[.diskActivity] = 5
        paces[.sensors] = modules.contains(.fans) ? 5 : 10
        return paces
    }

    /// True when a metric last read at `last` is due again. Half a second of slack keeps a 5 s pace from
    /// slipping to the tick after next.
    static func isDue(last: Date?, pace: TimeInterval?, at date: Date) -> Bool {
        guard let pace, let last else { return true }
        return date.timeIntervalSince(last) >= pace - 0.5 || last > date
    }
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

    /// The interface the Network module follows. Nil adds up all of them.
    public var networkInterface: String?

    /// The GPU the module shows. Everything reads the first one, so this one goes first.
    public var gpuName: String? {
        didSet {
            gpus = gpus.startingWith(gpuName)
        }
    }

    /// The volume the Disk module shows. Nil keeps the startup disk first.
    public var volumePath: String? {
        didSet {
            volumes = volumes.startingWith(volumePath)
        }
    }

    /// Which volumes can be ejected from here.
    public var ejectOptions = EjectOptions()

    public var ejectableVolumes: [DiskVolume] {
        volumes.filter(ejectOptions.allows)
    }

    /// Timers, notes and other small modules, ticking along with the monitor.
    public let everyday: EverydayStore
    /// Git, Docker, Ping and the other developer modules, each at its own pace.
    public let developer = DeveloperStore()
    /// Calendar events and reminders.
    public let agenda = AgendaStore()
    /// Screen time, commands, endpoints and GitHub.
    public let activity = ActivityStore()
    /// What each app uses, and its history.
    public let apps: AppUsageStore
    /// The user's own photos and birthdays, for the widgets they turned on.
    public let personal: PersonalWidgetStore
    /// Looks words up in the system dictionary for the Word of the Day widget.
    public let wordOfDay = WordOfDayProvider()
    /// These only reach the network or the disk once the app asks them to.
    public let weather: WeatherStore
    public let rates: RatesStore
    public let clipboard: ClipboardStore
    public let shelf: ShelfStore
    /// The adapter process runs only while `demand.nowPlaying` is set.
    public let nowPlaying: NowPlayingStore

    public var demand = MonitorDemand() {
        didSet {
            // A panel that opens or a module that appears should not wait out a long sleep.
            if demand != oldValue {
                sleeper.wake()
            }
        }
    }

    public var interval: TimeInterval = 2
    public var slowInterval: TimeInterval = 30
    /// Reads half as often on battery and a quarter as often in Low Power Mode.
    public var slowsOnBattery = true

    /// The Weather place the user picked for the sun, if any.
    public var sunPlaceID: Int?

    /// Where the Sun and Moon item, its panel and the sun widgets all look.
    public var sunPlace: WeatherPlace? {
        SunLocation.place(in: weather.places, chosen: sunPlaceID)
    }

    /// Called after each read. Menu bar items redraw from here, without SwiftUI's update machinery.
    @ObservationIgnored public var onUpdate: (() -> Void)?

    @ObservationIgnored let sampler = Sampler()
    @ObservationIgnored var loop: Task<Void, Never>?
    @ObservationIgnored var isWatchingStores = false
    @ObservationIgnored private var pausedLoop: Task<Void, Never>?
    /// How often timers and Keep Awake are looked at while nothing else is read.
    @ObservationIgnored var pausedInterval: TimeInterval = 5
    @ObservationIgnored let sleeper = LoopSleeper()
    @ObservationIgnored var powerWatcher: PowerSourceWatcher?
    @ObservationIgnored var volumeWatcher: VolumeWatcher?
    /// A power or volume event came in and the next tick reads the thing it is about.
    @ObservationIgnored var batteryEvent = false
    @ObservationIgnored var volumesEvent = false
    @ObservationIgnored var lastBattery: Date?
    @ObservationIgnored var lastVolumes: Date?
    @ObservationIgnored var lastSlow = Date.distantPast
    @ObservationIgnored var lastDevices = Date.distantPast
    @ObservationIgnored var lastTimeMachine = Date.distantPast
    /// An empty list before the first answer would read as "no devices".
    @ObservationIgnored private var hasReadDevices = false

    /// `system_profiler` takes seconds and batteries drain slowly, and backups run hourly at most.
    static let occasionalInterval: TimeInterval = 300

    public init(
        weather: WeatherStore = WeatherStore(),
        rates: RatesStore = RatesStore(),
        clipboard: ClipboardStore = ClipboardStore(),
        shelf: ShelfStore = ShelfStore(),
        nowPlaying: NowPlayingStore = NowPlayingStore(),
        apps: AppUsageStore = AppUsageStore(),
        personal: PersonalWidgetStore = PersonalWidgetStore(),
        everyday: EverydayStore = EverydayStore()
    ) {
        self.everyday = everyday
        self.apps = apps
        self.personal = personal
        self.weather = weather
        self.rates = rates
        self.clipboard = clipboard
        self.shelf = shelf
        self.nowPlaying = nowPlaying
        developer.onChange = { [weak self] in self?.onUpdate?() }
        nowPlaying.onUpdate = { [weak self] in self?.onUpdate?() }
        shelf.onChange = { [weak self] in self?.onUpdate?() }
    }

    public var isRunning: Bool {
        loop != nil
    }

    public func start() {
        guard loop == nil else { return }
        pausedLoop?.cancel()
        pausedLoop = nil
        sleeper.reset()
        wakeWhenStoresNeedTicks()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await tick()
                // A loop stopped during its tick must not sleep on the sleeper the next loop uses.
                guard !Task.isCancelled else { return }
                await sleeper.sleep(for: waitUntilNextRead())
            }
        }
    }

    /// Nothing is read while the Mac sleeps or the screen is locked, except for what timers and Keep Awake need.
    public func stop() {
        loop?.cancel()
        loop = nil
        powerWatcher = nil
        volumeWatcher = nil
        nowPlaying.stop()
        keepTimeWhilePaused()
    }

    /// A timer has to ring and Keep Awake has to end with the display off, when the regular tick is paused.
    private func keepTimeWhilePaused() {
        guard pausedLoop == nil else { return }
        pausedLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.pausedInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                everyday.tick(at: Date(), battery: everyday.isKeepingAwake ? BatteryReader.sample() : nil)
            }
        }
    }

    /// One read of what `kinds` want and the regular tick does not cover.
    ///
    /// This serves system widgets, which refresh once a minute: sampling them on every tick would cost far more.
    public func readForWidgets(_ kinds: Set<WidgetKind>) async {
        var extra = MonitorDemand(widgets: kinds).subtracting(demand)
        guard isRunning, extra.readsSamples else { return }
        // Once a minute is rare enough, and a widget must not wait for the monitor's own pace.
        extra.sensorDetail = .live
        await apply(
            sampler.read(extra, includeSlow: true, events: .all, temperature: temperatureSource),
            at: Date()
        )
    }

    /// What `kinds` show, from the latest readings. Nothing is read here, so calling it often costs little.
    public func widgetSnapshot(for kinds: Set<WidgetKind>, at date: Date = Date()) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: date)
        snapshot.temperatureUnit = Format.temperatureUnit
        snapshot.cpu = cpu
        snapshot.cpuInfo = cpuInfo
        snapshot.memory = memory
        snapshot.gpu = gpus.first
        snapshot.battery = battery
        snapshot.volumes = volumes.map { volume in
            var shown = volume
            shown.isEjectable = ejectOptions.allows(volume)
            return shown
        }
        snapshot.network = network
        snapshot.sensors = sensors?.cappedForWidgets()
        if !kinds.isDisjoint(with: [.activity, .topApps]) {
            snapshot.processes = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(12))
            snapshot.apps = apps.apps.sorted(by: .cpu).prefix(12).map {
                ProcessUsage(pid: $0.pid, name: $0.name, cpu: $0.cpu, memory: $0.memory)
            }
        }
        snapshot.everyday = everyday.data
        snapshot.events = agenda.events
        let todos = WidgetTodoSummary.capped(agenda.todos)
        snapshot.todos = todos.items
        snapshot.todoSummary = todos.summary
        snapshot.remindersAccess = agenda.remindersAccess
        snapshot.bootTime = SystemClock.bootTime()
        if !kinds.isDisjoint(with: WidgetKind.screenTimeKinds) {
            snapshot.screenTime = activity.screenTime
        }
        snapshot.commandResults = activity.commandResults
        snapshot.endpointChecks = activity.endpointChecks
        snapshot.reviews = activity.reviews
        snapshot.runs = activity.runs
        snapshot.contributions = activity.contributions
        if kinds.contains(.github) {
            snapshot.github = activity.github
        }
        if !kinds.isDisjoint(with: WidgetKind.personalKinds) {
            snapshot.personal = personal.data
        }
        snapshot.place = sunPlace
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
    ///
    /// - Parameter includingSlow: Also reads what normally waits for the slow pace, such as disk space, for a
    ///   screen that would otherwise stay empty until then.
    public func refresh(includingSlow: Bool = false) {
        if includingSlow {
            lastSlow = .distantPast
            lastBattery = nil
            lastVolumes = nil
        }
        Task { await tick() }
    }

    public func points(_ metric: Metric, in range: TieredHistory.Range) -> [History<Double>.Point] {
        histories[metric]?.points(in: range) ?? []
    }

    public func fanPoints(_ fan: Int, in range: TieredHistory.Range) -> [History<Double>.Point] {
        fanHistories[fan]?.points(in: range) ?? []
    }

    /// Battery power halves the polling rate and Low Power Mode quarters it.
    var effectiveInterval: TimeInterval {
        guard slowsOnBattery else { return interval }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return interval * 4
        }
        return battery?.isOnAC == false ? interval * 2 : interval
    }

    private func tick() async {
        let now = Date()
        watchEvents()
        let includeSlow = now.timeIntervalSince(lastSlow) >= slowInterval
        if includeSlow {
            lastSlow = now
        }
        var events: EventReads = []
        if demand.battery, ReadSchedule.isDue(
            last: lastBattery, interval: eventDrivenInterval, event: batteryEvent, at: now
        ) {
            events.insert(.battery)
            lastBattery = now
            batteryEvent = false
        }
        if demand.disk, ReadSchedule.isDue(
            last: lastVolumes, interval: eventDrivenInterval, event: volumesEvent, at: now
        ) {
            events.insert(.volumes)
            lastVolumes = now
            volumesEvent = false
        }
        let reading = await sampler.read(
            demand, includeSlow: includeSlow, events: events, temperature: temperatureSource
        )
        apply(reading, at: now)
        everyday.tick(at: now, battery: battery)
        developer.tick(at: now, demand: demand.developer, live: demand.developerLive)
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
            gpus = value.startingWith(gpuName)
            // A GPU that reports no figure leaves no false 0% in the history.
            if let utilization = gpus.first?.utilization {
                record(.gpu, utilization, date)
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
        if let value = reading.network?.only(networkInterface) {
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
            volumes = value.startingWith(volumePath)
        }
    }

    private func record(_ metric: Metric, _ value: Double, _ date: Date) {
        histories[metric, default: TieredHistory()].append(value, at: date)
    }
}

extension Array where Element: Identifiable, Element.ID == String {
    /// The chosen one first and the rest in their order. A choice that is gone changes nothing.
    func startingWith(_ id: String?) -> [Element] {
        guard let id, let index = firstIndex(where: { $0.id == id }) else { return self }
        var ordered = self
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }
}
