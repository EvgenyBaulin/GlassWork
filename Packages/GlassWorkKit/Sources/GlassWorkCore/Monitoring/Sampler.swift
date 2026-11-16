import Foundation

/// Reads that follow events rather than every tick.
struct EventReads: OptionSet, Sendable {
    let rawValue: Int
    static let battery = EventReads(rawValue: 1)
    static let volumes = EventReads(rawValue: 2)
    static let all: EventReads = [.battery, .volumes]
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
    private var sensorPace = SensorPace()
    private var lastRead: [SampleKind: Date] = [:]

    /// Whether a metric is wanted and due, noting the read when it is.
    private func takes(_ kind: SampleKind, wanted: Bool, demand: MonitorDemand, at date: Date) -> Bool {
        guard wanted, SampleKind.isDue(last: lastRead[kind], pace: demand.paces[kind], at: date) else { return false }
        lastRead[kind] = date
        return true
    }

    /// - Parameter temperature: What the temperature graph records, which the summary has to include.
    func read(
        _ demand: MonitorDemand,
        includeSlow: Bool,
        events: EventReads,
        temperature: SensorChoice
    ) async -> Reading {
        var reading = Reading()
        let now = Date()
        if takes(.cpu, wanted: demand.cpu, demand: demand, at: now) {
            readCPU(into: &reading)
        }
        if takes(.memory, wanted: demand.memory, demand: demand, at: now) {
            reading.memory = MemoryReader.sample()
        }
        if demand.network {
            reading.network = readNetwork()
        }
        if takes(.diskActivity, wanted: demand.disk, demand: demand, at: now) {
            reading.diskActivity = readDisk()
        }
        if takes(.gpu, wanted: demand.gpu, demand: demand, at: now) {
            reading.gpus = GPUReader.samples()
        }
        if demand.sensors, sensorPace.isDue(demand.sensorDetail, at: now),
           takes(.sensors, wanted: true, demand: demand, at: now)
        {
            // Alerts watch the average CPU temperature, whatever the graph shows.
            let summary: Set<SensorChoice> = [temperature, .averageCPU]
            reading.sensors = sensorReader?.sample(showing: demand.sensorDetail == .summary ? summary : nil)
        }
        if demand.processes || (includeSlow && demand.slowProcesses) {
            reading.processes = await ProcessList.read()
        }
        if demand.disk, events.contains(.volumes) {
            reading.volumes = DiskReader.volumes()
        }
        if demand.battery, events.contains(.battery) {
            reading.battery = BatteryReader.sample()
        }
        return reading
    }

    /// What the loop has to wait for, from what each demanded metric last read.
    func plan(for demand: MonitorDemand, at now: Date) -> ReadPlan {
        var plan = ReadPlan()
        if demand.network || demand.processes {
            plan.everyTick = true
        }
        for kind in SampleKind.allCases where demand.wants(kind) {
            let pace = demand.paces[kind]
            let sensorDate = kind == .sensors ? sensorPace.nextDue(demand.sensorDetail) : nil
            if pace == nil, kind != .sensors || sensorDate == nil {
                plan.everyTick = true
                continue
            }
            let paced = pace.map { _ in ReadSchedule.dueDate(last: lastRead[kind], pace: pace, now: now) }
            plan.dates.append(max(paced ?? .distantPast, sensorDate ?? .distantPast))
        }
        return plan
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
