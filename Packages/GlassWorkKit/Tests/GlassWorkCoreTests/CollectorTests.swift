import Foundation
@testable import GlassWorkCore
import Testing

struct CPUSampleTests {
    @Test func computesSharesFromTickDeltas() throws {
        let old = [CPUTicks(user: 100, system: 50, idle: 800, nice: 0), CPUTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let new = [
            CPUTicks(user: 130, system: 60, idle: 860, nice: 0),
            CPUTicks(user: 0, system: 0, idle: 100, nice: 0),
        ]

        let sample = try #require(CPUSample.between(old, new))

        #expect(abs(sample.total - 40.0 / 200) < 0.0001)
        #expect(abs(sample.user - 30.0 / 200) < 0.0001)
        #expect(abs(sample.cores[0] - 0.4) < 0.0001)
        #expect(sample.cores[1] == 0)
    }

    @Test func rejectsMismatchedSnapshots() {
        #expect(CPUSample.between([], [CPUTicks(user: 1, system: 1, idle: 1, nice: 0)]) == nil)
    }

    @Test func readsLiveTicks() {
        #expect(!CPUReader.ticks().isEmpty)
    }
}

struct MemoryTests {
    @Test func countsMemoryLikeActivityMonitor() {
        let counters = VMCounters(
            pageSize: 100, free: 10, wired: 20, compressor: 30, purgeable: 5, external: 7, internal: 45
        )
        let sample = counters.sample(total: 20000, swapUsed: 1, swapTotal: 2, pressure: .normal)

        #expect(sample.app == 4000)
        #expect(sample.wired == 2000)
        #expect(sample.compressed == 3000)
        #expect(sample.cached == 1200)
        #expect(sample.used == 9000)
        #expect(sample.usedShare == 0.45)
    }

    @Test(arguments: [(1, MemoryPressure.normal), (2, .warning), (4, .critical)])
    func mapsPressureLevels(level: Int, expected: MemoryPressure) {
        #expect(MemoryPressure(level: level) == expected)
    }

    @Test func readsLiveMemory() throws {
        let sample = try #require(MemoryReader.sample())
        #expect(sample.used > 0 && sample.used <= sample.total)
    }
}

struct NetworkTests {
    @Test func sumsPhysicalInterfacesOnly() {
        let old = [
            InterfaceCounters(name: "en0", received: 1000, sent: 100),
            InterfaceCounters(name: "utun3", received: 0, sent: 0),
        ]
        let new = [
            InterfaceCounters(name: "en0", received: 3000, sent: 300),
            InterfaceCounters(name: "utun3", received: 2000, sent: 200),
        ]

        let sample = NetworkSample.between(old, new, seconds: 2, sessionReceived: 10, sessionSent: 1)

        #expect(sample.download == 1000)
        #expect(sample.upload == 100)
        #expect(sample.interfaces.map(\.name) == ["en0"])
        #expect(sample.sessionReceived == 2010)
        #expect(sample.sessionSent == 201)
    }

    @Test func treatsCounterResetAsZero() {
        let old = [InterfaceCounters(name: "en0", received: 5000, sent: 500)]
        let new = [InterfaceCounters(name: "en0", received: 10, sent: 1)]
        #expect(NetworkSample.between(old, new, seconds: 2).download == 0)
    }

    @Test func readsLiveCounters() {
        #expect(!NetworkReader.counters().isEmpty)
    }
}

struct SensorTests {
    @Test(arguments: [
        ("Tp0a", SensorGroup.cpuPerformance), ("Te04", .cpuEfficiency), ("Tg0K", .gpu), ("Ts00", .soc),
        ("TB0T", .battery), ("TH0a", .storage), ("TPD0", .power), ("TaLP", .ambient), ("TD00", .other),
    ])
    func groupsKeys(key: String, group: SensorGroup) {
        #expect(SensorGroup(key: key) == group)
    }

    @Test func averagesCPUGroups() {
        let sample = SensorSample(readings: [
            SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 50),
            SensorReading(key: "Te01", group: .cpuEfficiency, celsius: 40),
            SensorReading(key: "Tg01", group: .gpu, celsius: 90),
        ], fans: [])
        #expect(sample.averageCPU == 45)
        #expect(sample.averageGPU == 90)
        #expect(sample.averageFanRPM == nil)
    }

    @Test(arguments: [(0.0, false), (-3.1, false), (45.0, true), (200.0, false)])
    func filtersImplausibleValues(celsius: Double, expected: Bool) {
        #expect(SensorSample.isPlausible(celsius) == expected)
    }

    @Test func decodesSMCValues() {
        let float = SMCClient.Value(type: "flt ", bytes: [0, 0, 0x34, 0x42])
        let fixed = SMCClient.Value(type: "sp78", bytes: [0x2D, 0x80])
        let integer = SMCClient.Value(type: "ui16", bytes: [0x01, 0x00])
        #expect(float.number == 45)
        #expect(fixed.number == 45.5)
        #expect(integer.number == 256)
        #expect(SMCClient.Value(type: "ch8*", bytes: [1]).number == nil)
    }

    @Test func fanShareStaysInsideItsRange() {
        let fan = FanReading(id: 0, rpm: 3000, minimum: 1000, maximum: 5000, target: 0, isManual: false)
        #expect(fan.share == 0.5)
    }
}

struct ProcessListTests {
    @Test func parsesPsOutput() {
        let output = """
          123  18.2 269024 WindowServer
           77   0,4   1024 Google Chrome Helper
        broken line
        """
        let list = ProcessList.parse(output)
        #expect(list.count == 2)
        #expect(list[0] == ProcessUsage(pid: 123, name: "WindowServer", cpu: 18.2, memory: 269_024 * 1024))
        #expect(list[1].name == "Google Chrome Helper")
        #expect(list[1].cpu == 0.4)
    }
}

struct BatteryTests {
    @Test func parsesChargingBattery() {
        let sample = BatteryReader.parse(
            [
                "Current Capacity": 82,
                "Max Capacity": 100,
                "Is Charging": true,
                "Time to Full Charge": 65,
                "Power Source State": "AC Power",
            ],
            smart: [
                "CycleCount": 120,
                "DesignCapacity": 5000,
                "NominalChargeCapacity": 4500,
                "Temperature": 3050,
                "AdapterDetails": ["Watts": 96],
            ]
        )
        #expect(sample.charge == 0.82)
        #expect(sample.isCharging && sample.isOnAC)
        #expect(sample.minutesRemaining == 65)
        #expect(sample.health == 0.9)
        #expect(sample.cycleCount == 120)
        #expect(sample.temperature == 30.5)
        #expect(sample.adapterWatts == 96)
    }

    @Test func hidesEstimateWhileCalculating() {
        let sample = BatteryReader.parse(["Current Capacity": 50, "Time to Empty": -1], smart: [:])
        #expect(sample.minutesRemaining == nil)
        #expect(sample.isOnAC == false)
    }
}

struct GPUTests {
    @Test func readsDriverStatistics() throws {
        let sample = try #require(GPUReader.parse([
            "model": "Apple M3 Pro",
            "PerformanceStatistics": [
                "Device Utilization %": 43,
                "Renderer Utilization %": 42,
                "Tiler Utilization %": 41,
            ],
        ]))
        #expect(sample.name == "Apple M3 Pro")
        #expect(sample.device == 0.43)
        #expect(GPUReader.parse([:]) == nil)
    }
}

struct DiskTests {
    @Test func computesRates() {
        let activity = DiskActivity.between(
            DiskCounters(read: 100, written: 500),
            DiskCounters(read: 300, written: 100),
            seconds: 2
        )
        #expect(activity.read == 100)
        #expect(activity.write == 0)
    }

    @Test func listsStartupDiskFirst() throws {
        let first = try #require(DiskReader.volumes().first)
        #expect(first.path == "/")
        #expect(first.total > 0)
    }
}

struct DeviceBatteryTests {
    @Test func readsConnectedDevicesLowestFirst() {
        let json = #"""
        {"SPBluetoothDataType": [{"device_connected": [
            {"AirPods Pro": {"device_batteryLevelMain": "80%", "device_minorType": "Headphones"}},
            {"Magic Mouse": {"device_batteryLevel": "45%", "device_minorType": "Mouse"}},
            {"Speaker": {"device_minorType": "Speaker"}}
        ]}]}
        """#
        let devices = DeviceBatteryReader.parseBluetooth(Data(json.utf8))

        #expect(devices.map(\.name) == ["Magic Mouse", "AirPods Pro"])
        #expect(devices.first?.kind == .mouse)
        #expect(devices.last?.charge == 0.8)
    }

    @Test func toleratesEmptyOutput() {
        #expect(DeviceBatteryReader.parseBluetooth(Data()).isEmpty)
    }
}
