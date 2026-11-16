import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import SwiftUI
import Testing

private let islandNow = Date(timeIntervalSince1970: 1_794_831_360)

private enum IslandSample: String, CaseIterable {
    case meeting, timers, copied, charging, systemAlert, network, devServers, nowPlaying, keepAwake, inProgress
}

@MainActor
private enum IslandSamples {
    static let geometry = IslandGeometry(screen: IslandScreen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 32,
        auxiliaryLeftWidth: 628, auxiliaryRightWidth: 628, menuBarHeight: 32
    ))

    static var picture: Data? {
        let image = NSImage(size: CGSize(width: 360, height: 120), flipped: false) { rect in
            NSGradient(
                starting: NSColor(red: 0.2, green: 0.22, blue: 0.55, alpha: 1),
                ending: NSColor(red: 0.78, green: 0.61, blue: 0.81, alpha: 1)
            )?.draw(in: rect, angle: 0)
            return true
        }
        return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
            .representation(using: .png, properties: [:])
    }

    static func input(_ sample: IslandSample) -> IslandInput {
        var input = IslandInput()
        switch sample {
        case .meeting:
            input.calendarEvents = [AgendaEvent(
                id: "review", title: "Design review", start: islandNow.addingTimeInterval(240),
                end: islandNow.addingTimeInterval(2040), location: "Zoom", callURL: URL(string: "https://zoom.us/j/123")
            )]
        case .inProgress:
            input = calendarInput()
        case .timers:
            input.timers = timers
        case .copied:
            input = clipboardInput()
        case .charging:
            input.battery = BatterySample(
                charge: 0.82,
                isCharging: true,
                isOnAC: true,
                minutesRemaining: 64,
                adapterWatts: 67
            )
        case .systemAlert:
            input = systemInput()
        case .network:
            input.wifi = .notConnected
            input.vpn = VPNReading(services: [VPNService(
                id: "office",
                name: "Office VPN",
                kind: "IPSec",
                status: .disconnected
            )], tunnels: [])
            input.ping = .reply(milliseconds: 18)
            input.previousPing = .reply(milliseconds: 640)
            input.pingHost = "1.1.1.1"
        case .devServers:
            input.docker = .containers([container(running: false)], context: "pocket-api")
            input.devServers = .servers([
                DevServer(port: 5173, pid: 17, process: "node", tool: "vite", project: "pocket-api", kind: .web),
                DevServer(port: 8080, pid: 18, process: "api", project: "pocket-api", kind: .web),
            ])
        case .nowPlaying:
            input = playbackInput()
        case .keepAwake:
            input.keepAwakeIncludesDisplay = true
            input.isKeepingAwake = true
            input.keepAwakeEnds = islandNow.addingTimeInterval(84)
        }
        return input
    }

    static func calendarInput() -> IslandInput {
        var input = IslandInput()
        input.calendarEvents = [
            AgendaEvent(
                id: "class",
                title: "Эконометрика",
                start: islandNow.addingTimeInterval(-540),
                end: islandNow.addingTimeInterval(161),
                location: "M303"
            ),
            AgendaEvent(
                id: "next",
                title: "Пары Ани",
                start: islandNow.addingTimeInterval(86400),
                end: islandNow.addingTimeInterval(90000)
            ),
        ]
        return input
    }

    static func clipboardInput() -> IslandInput {
        var input = IslandInput()
        var entry = ClipboardEntry(
            kind: .image,
            text: "",
            byteCount: 1_200_000,
            appName: "Screenshot",
            date: islandNow,
            fingerprint: "screenshot"
        )
        entry.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        entry.pixelWidth = 1440
        entry.pixelHeight = 900
        input.clipboardEntry = entry
        input.clipboardPreview = picture
        return input
    }

    static func systemInput() -> IslandInput {
        var input = IslandInput()
        input.sensors = SensorSample(
            readings: [SensorReading(key: "Tp01", group: .cpuPerformance, celsius: 98)],
            fans: [FanReading(id: 0, rpm: 5800, minimum: 1200, maximum: 6000)]
        )
        input.processes = [ProcessUsage(pid: 42, name: "xcodebuild", cpu: 412, memory: 100_000_000)]
        input.volumes = [DiskVolume(
            name: "Macintosh HD",
            path: "/",
            total: 500_000_000_000,
            free: 6_000_000_000,
            isInternal: true,
            isEjectable: false
        )]
        return input
    }

    static func playbackInput() -> IslandInput {
        var input = IslandInput()
        var session = NowPlayingSession(
            track: NowPlayingTrack(
                title: "Midnight Drive",
                artist: "ZincWolf",
                album: "Night Shift",
                duration: 354
            ),
            isPlaying: true, elapsed: 84, elapsedAt: islandNow
        )
        session.appName = "Music"
        session.canGoNext = true
        session.canGoPrevious = true
        session.canSeek = true
        input.nowPlaying = session
        input.artwork = picture
        input.outputDevice = "AirPods Pro"
        return input
    }

    static var timers: [CountdownTimer] {
        [
            CountdownTimer(title: "Tea", duration: 180, start: islandNow.addingTimeInterval(-19)),
            CountdownTimer(title: "Laundry", duration: 2700, start: islandNow.addingTimeInterval(-1250)),
            CountdownTimer(title: "Pasta", duration: 600, start: islandNow.addingTimeInterval(-672)),
        ]
    }

    static func container(running: Bool) -> DockerContainer {
        DockerContainer(
            id: "db",
            name: "api-db",
            image: "docker",
            status: running ? "Up" : "Exited (1)",
            isRunning: running,
            ports: []
        )
    }

    static func store(_ sample: IslandSample, expanded: Bool = false) -> IslandStore {
        let store = IslandStore()
        let input = input(sample)
        var previous = input
        switch sample {
        case .copied: previous.clipboardEntry = nil
        case .charging: previous.battery?.isOnAC = false
        case .network:
            previous.wifi = .connected(WiFiLink(
                rssi: -50,
                noise: -90,
                transmitRate: 800,
                channel: 36,
                bandCode: 2,
                widthCode: 3,
                phyCode: 6
            ))
        case .devServers: previous.docker = .containers([container(running: true)], context: "pocket-api")
        default: break
        }
        store.update(input: previous, now: islandNow.addingTimeInterval(-120))
        store.update(input: input, now: islandNow)
        if expanded {
            store.lifecycle.clicked()
        }
        return store
    }
}

private struct IslandBackdrop: View {
    let dark: Bool

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.25, green: 0.24, blue: 0.48), Color(red: 0.52, green: 0.40, blue: 0.73)]
                    : [Color(red: 0.96, green: 0.95, blue: 1), Color(red: 0.82, green: 0.78, blue: 0.94)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Color.purple.opacity(0.08).frame(height: 120).rotationEffect(.degrees(3)).offset(y: 100)
            HStack(spacing: 12) {
                Text("Finder").fontWeight(.medium)
                Text("File")
                Text("Edit")
                Spacer()
                Text("Mon 16 Nov  15:16")
            }
            .font(.system(size: 13))
            .foregroundStyle(dark ? .white : .black.opacity(0.85))
            .padding(.horizontal, 22).frame(height: 32)
        }
        .clipped()
    }
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct IslandSnapshotTests {
    private func render(
        _ store: IslandStore,
        name: String,
        dark: Bool,
        height: CGFloat = 120,
        geometry: IslandGeometry = IslandSamples.geometry,
        russian _: Bool = false
    ) {
        var island = IslandView(store: store, geometry: geometry)
        island.fixedNow = islandNow
        let view = ZStack(alignment: .top) {
            IslandBackdrop(dark: dark)
            island
        }
        .frame(width: 620, height: height)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 3 * 3600)!)
        .transaction { $0.animation = nil; $0.disablesAnimations = true }
        snapshotPanel(view, name: name, dark: dark, testName: "island")
    }

    @Test func compact() {
        for sample in IslandSample.allCases {
            for dark in [true, false] {
                render(IslandSamples.store(sample), name: "compact-\(sample.rawValue)", dark: dark)
            }
        }
    }

    @Test func expanded() {
        for sample in IslandSample.allCases {
            for dark in [true, false] {
                render(
                    IslandSamples.store(sample, expanded: true),
                    name: "expanded-\(sample.rawValue)",
                    dark: dark,
                    height: 370
                )
            }
        }
    }

    @Test func lifecycle() {
        for dark in [true, false] {
            let store = IslandStore()
            render(store, name: "idle", dark: dark)
            store.lifecycle.pointerEntered(at: islandNow.addingTimeInterval(-1))
            store.tick(now: islandNow)
            render(store, name: "peek", dark: dark)
        }
    }

    @Test func queue() {
        for dark in [true, false] {
            let store = IslandStore()
            var input = IslandSamples.input(.meeting)
            input.timers = IslandSamples.input(.timers).timers
            input.isKeepingAwake = true
            input.keepAwakeEnds = islandNow.addingTimeInterval(84)
            store.update(input: input, now: islandNow)
            render(store, name: "split-more", dark: dark)
            store.lifecycle.clicked()
            render(store, name: "expanded-pages", dark: dark, height: 240)
            store.showPage(1)
            render(store, name: "expanded-pages-timers", dark: dark, height: 370)
        }
    }

    @Test func meetingWithoutLink() {
        for dark in [true, false] {
            let store = IslandStore()
            var input = IslandSamples.input(.meeting)
            input.calendarEvents[0].callURL = nil
            store.update(input: input, now: islandNow)
            store.lifecycle.clicked()
            render(store, name: "meeting-no-link", dark: dark, height: 220)
        }
    }

    @Test func clipboardKinds() {
        let samples: [(ClipboardKind, String)] = [
            (.text, "Meeting moved to 15:00 — see you there"), (.link, "https://example.com/review"),
            (.color, "#6B5BB5"), (.file, "/Documents/invoice.pdf"),
        ]
        for (kind, text) in samples {
            for dark in [true, false] {
                let store = IslandStore()
                store.update(input: IslandInput(), now: islandNow)
                var input = IslandInput()
                input.clipboardEntry = ClipboardEntry(
                    kind: kind,
                    text: text,
                    byteCount: text.utf8.count,
                    appName: "Finder",
                    date: islandNow,
                    fingerprint: text
                )
                store.update(input: input, now: islandNow)
                store.lifecycle.clicked()
                render(store, name: "clipboard-\(kind.rawValue)", dark: dark, height: 330)
            }
        }
    }

    @Test func diskWarningWithNormalTemperature() {
        for dark in [true, false] {
            let store = IslandStore()
            var input = IslandSamples.input(.systemAlert)
            input.sensors?.readings[0].celsius = 45
            store.update(input: input, now: islandNow)
            store.lifecycle.clicked()
            render(store, name: "disk-warning", dark: dark, height: 330)
        }
    }

    @Test func noHardwareNotch() {
        let geometry = IslandGeometry(screen: IslandScreen(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            safeAreaTop: 0,
            menuBarHeight: 24
        ))
        for dark in [true, false] {
            render(IslandSamples.store(.timers), name: "no-notch", dark: dark, geometry: geometry)
        }
    }
}
