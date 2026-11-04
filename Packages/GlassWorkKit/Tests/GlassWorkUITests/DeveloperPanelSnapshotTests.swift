import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Draws a panel the way the app does, at its natural height.
@MainActor
func snapshotPanel(
    _ view: some View,
    name: String,
    dark: Bool = true,
    fileID: StaticString = #fileID,
    file: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    let scheme: ColorScheme = dark ? .dark : .light
    let root = view
        .environment(\.colorScheme, scheme)
        .background(dark ? Color(white: 0.12) : Color(white: 0.96))
    let host = NSHostingView(rootView: root)
    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
    withSnapshotTesting(record: record ? .all : .missing) {
        assertSnapshot(
            of: host,
            as: .image(precision: 0.98),
            named: name + (dark ? "-dark" : "-light"),
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct DeveloperPanelSnapshotTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func pingLog(_ values: [Double?]) -> PingLog {
        var log = PingLog()
        for (index, value) in values.enumerated() {
            let outcome: PingOutcome = value.map { .reply(milliseconds: $0) } ?? .timeout
            log.append(outcome, at: start.addingTimeInterval(Double(index) * 30))
        }
        return log
    }

    @Test(arguments: [true, false])
    func ping(dark: Bool) {
        let values: [Double?] = [14, 16, 15, 18, 46, 19, 15, 14, 17, nil, 16, 18, 15, 22, 16, 14]
        snapshotPanel(PingPanel(log: pingLog(values), host: "1.1.1.1"), name: "ping", dark: dark)
    }

    @Test func pingHostDown() {
        snapshotPanel(PingPanel(log: pingLog([14, 15, nil, nil, nil]), host: "10.0.0.9"), name: "ping-down")
    }

    @Test(arguments: [true, false])
    func vpn(dark: Bool) {
        let reading = VPNReading(
            services: [
                VPNService(id: "1", name: "Work VPN", kind: "VPN", status: .connected),
                VPNService(id: "2", name: "Personal", kind: "IPSec", status: .disconnected),
            ],
            tunnels: [TunnelInterface(name: "utun4", address: "10.8.0.6")]
        )
        let panel = VPNPanel(reading: reading, since: start, now: start.addingTimeInterval(5040))
        snapshotPanel(panel, name: "vpn", dark: dark)
    }

    @Test func vpnNotConfigured() {
        snapshotPanel(VPNPanel(reading: VPNReading(services: [], tunnels: []), since: nil), name: "vpn-none")
    }

    @Test(arguments: [true, false])
    func wifi(dark: Bool) {
        let link = WiFiLink(
            rssi: -58, noise: -92, transmitRate: 866, channel: 44, bandCode: 2, widthCode: 3, phyCode: 6
        )
        let signal = [-62, -60, -58, -58, -55, -58, -60, -57, -58, -70, -62, -58, -58].enumerated().map { index, rssi in
            History<Double>.Point(date: start.addingTimeInterval(Double(index) * 5), value: WiFiSignal.plotted(rssi))
        }
        snapshotPanel(WiFiPanel(reading: .connected(link), signal: signal), name: "wifi", dark: dark)
    }

    @Test func wifiOff() {
        snapshotPanel(WiFiPanel(reading: .off, signal: []), name: "wifi-off")
    }

    @Test(arguments: [true, false])
    func docker(dark: Bool) {
        let containers = [
            DockerContainer(
                id: "3f2a", name: "postgres-dev", image: "postgres:16", status: "Up 2 hours",
                isRunning: true, ports: ["5432→5432"]
            ),
            DockerContainer(
                id: "8e41", name: "minio", image: "minio/minio", status: "Up 2 hours",
                isRunning: true, ports: ["9000-9001"]
            ),
            DockerContainer(
                id: "1b9f", name: "worker", image: "pocket-api-worker", status: "Exited (0) 3 hours ago",
                isRunning: false, ports: []
            ),
        ]
        snapshotPanel(DockerPanel(reading: .containers(containers, context: "orbstack")), name: "docker", dark: dark)
    }

    @Test func dockerNotRunning() {
        snapshotPanel(DockerPanel(reading: .notRunning), name: "docker-off")
    }

    @Test(arguments: [true, false])
    func devServers(dark: Bool) {
        let servers = [
            DevServer(
                port: 3000, pid: 1, process: "node", tool: "next dev", project: "pocket-api", kind: .web, uptime: 7200
            ),
            DevServer(
                port: 8080, pid: 2, process: "python3", tool: "http.server", project: "~/Downloads", kind: .web,
                uptime: 240
            ),
            DevServer(
                port: 5432, pid: 3, process: "postgres", project: "postgresql@16", kind: .service, uptime: 259_200
            ),
        ]
        snapshotPanel(DevServersPanel(reading: .servers(servers)), name: "dev-servers", dark: dark)
    }

    @Test func devServersEmpty() {
        snapshotPanel(DevServersPanel(reading: .servers([])), name: "dev-servers-empty")
    }
}

@MainActor
struct DeveloperItemTests {
    @Test func pingTurnsRedOnlyWhenTheHostIsDown() {
        var log = PingLog()
        log.append(.reply(milliseconds: 18.4), at: Date())
        #expect(ItemContent.ping(log).figure == "18 ms")
        #expect(ItemContent.ping(log).alert == nil)

        for _ in 0 ..< 3 {
            log.append(.timeout, at: Date())
        }
        #expect(ItemContent.ping(log).alert == Palette.red)
    }

    @Test func offlineIsFaintNotRed() {
        var log = PingLog()
        for _ in 0 ..< 3 {
            log.append(.offline, at: Date())
        }
        let item = ItemContent.ping(log)

        #expect(item.alert == nil)
        #expect(item.isFaint)
    }

    @Test func connectedVPNIsAGreenFilledShield() {
        let connected = VPNReading(services: [], tunnels: [TunnelInterface(name: "utun4", address: "10.8.0.6")])
        let item = ItemContent.vpn(connected)

        #expect(item.symbol == "shield.fill")
        #expect(item.alert == Palette.green)
        #expect(item.figure == "On")
    }

    @Test func noVPNIsAFaintOutline() {
        let item = ItemContent.vpn(VPNReading(services: [], tunnels: []))

        #expect(item.symbol == "shield")
        #expect(item.alert == nil)
        #expect(item.isFaint)
    }

    @Test func wifiShowsBarsAndDecibels() {
        let link = WiFiLink(rssi: -65, noise: -90, transmitRate: 1, channel: 1, bandCode: 2, widthCode: 3, phyCode: 6)
        let item = ItemContent.wifi(.connected(link), signal: [35])

        #expect(item.figure == "−65 dBm")
        #expect(item.symbolLevel == 2.0 / 3)
    }

    @Test func wifiOffIsSlashed() {
        #expect(ItemContent.wifi(.off, signal: []).symbol == "wifi.slash")
    }

    @Test func dockerDotsShowRunningAndStopped() {
        let containers = [true, true, false].enumerated().map { index, isRunning in
            DockerContainer(id: "\(index)", name: "c", image: "i", status: "s", isRunning: isRunning, ports: [])
        }
        let item = ItemContent.docker(.containers(containers, context: nil))

        #expect(item.figure == "2")
        #expect(item.glyph == .dots(filled: 2, faint: 1))
    }

    @Test func stoppedEngineIsFaint() {
        let item = ItemContent.docker(.notRunning)

        #expect(item.figure == "—")
        #expect(item.isFaint)
    }

    @Test func devServersCount() {
        let server = DevServer(port: 3000, pid: 1, process: "node", project: "x", kind: .web)
        #expect(ItemContent.devServers(.servers([server])).figure == "1")
    }

    @Test func pingGraphShowsTheWholeLogNotTheLastMinute() {
        var log = PingLog()
        for index in 0 ..< 40 {
            log.append(.reply(milliseconds: Double(index)), at: Date())
        }
        #expect(ItemContent.ping(log).values?.count == 40)
    }
}
