import Foundation
@testable import GlassWorkCore

enum IslandFixtures {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let wifi = WiFiReading.connected(WiFiLink(
        rssi: -50, noise: -90, transmitRate: 400, channel: 36, bandCode: 2, widthCode: 3, phyCode: 6
    ))
    static let vpn = VPNReading(services: [], tunnels: [TunnelInterface(name: "utun1", address: "10.0.0.1")])
    static let vpnOff = VPNReading(services: [], tunnels: [])

    static func event(_ id: String = "event", startsIn: Double, endsIn: Double, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(
            id: id, title: "Planning", start: now.addingTimeInterval(startsIn), end: now.addingTimeInterval(endsIn),
            isAllDay: allDay, location: "Office", callURL: URL(string: "https://meet.google.com/test")
        )
    }

    static func battery(onAC: Bool) -> BatterySample {
        BatterySample(
            charge: 0.5, isCharging: onAC, isOnAC: onAC, minutesRemaining: 60,
            health: nil, cycleCount: nil, temperature: nil, adapterWatts: onAC ? 67 : nil
        )
    }

    static func volume(path: String = "/", free: UInt64) -> DiskVolume {
        DiskVolume(name: "Disk", path: path, total: 500_000_000_000, free: free, isInternal: true, isEjectable: false)
    }

    static func container(running: Bool) -> DockerContainer {
        DockerContainer(
            id: "db", name: "database", image: "postgres", status: running ? "Up" : "Exited",
            isRunning: running, ports: ["5432"]
        )
    }

    static func server(pid: Int32 = 42) -> DevServer {
        DevServer(port: 3000, pid: pid, process: "node", project: "site", kind: .web)
    }

    static func clipboard() -> ClipboardEntry {
        ClipboardEntry(
            kind: .text,
            text: "Copied text",
            byteCount: 11,
            appName: "Editor",
            date: now,
            fingerprint: "text"
        )
    }
}
