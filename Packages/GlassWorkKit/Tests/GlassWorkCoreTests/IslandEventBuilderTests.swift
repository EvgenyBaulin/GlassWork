import Foundation
@testable import GlassWorkCore
import Testing

struct IslandEventBuilderTests {
    private let now = IslandFixtures.now

    @Test func emptySnapshotProducesNothing() {
        #expect(build(IslandInput()).isEmpty)
    }

    @Test func meetingChoosesSoonestTimedEventAndPreservesJoinData() {
        var input = IslandInput()
        var declined = IslandFixtures.event("declined", startsIn: 1, endsIn: 500)
        declined.isDeclined = true
        let expected = IslandFixtures.event("next", startsIn: 100, endsIn: 600)
        input.calendarEvents = [
            IslandFixtures.event("later", startsIn: 200, endsIn: 600), declined,
            IslandFixtures.event("allDay", startsIn: 1, endsIn: 600, allDay: true), expected,
        ]
        let events = build(input)
        #expect(events.count == 1)
        #expect(events.first?.id == "meeting:next")
        #expect(events.first?.detail == .meeting(expected))
        #expect(events.first?.expires == nil)
    }

    @Test(arguments: [(0.0, false), (0.001, true), (299.999, true), (300, true), (300.001, false)])
    func meetingWindow(offset: Double, expected: Bool) {
        var input = IslandInput()
        input.calendarEvents = [IslandFixtures.event(startsIn: offset, endsIn: 1000)]
        #expect(build(input).contains { $0.kind == .meeting } == expected)
    }

    @Test(arguments: [
        (-1.0, 100.0, true),
        (0, 100, true),
        (-100, 0, false),
        (1, 100, false),
        (-172_800, 86399, true),
        (-172_800, 86400, false),
        (-172_800, 172_800, false)
    ])
    func inProgressWindow(start: Double, end: Double, expected: Bool) {
        var input = IslandInput()
        input.calendarEvents = [IslandFixtures.event(startsIn: start, endsIn: end)]
        #expect(build(input).contains { $0.kind == .inProgress } == expected)
    }

    @Test func inProgressChoosesSoonestEndAndSkipsAllDayOrDeclined() {
        var input = IslandInput()
        let expected = IslandFixtures.event("first", startsIn: -100, endsIn: 50)
        var declined = IslandFixtures.event("declined", startsIn: -100, endsIn: 10)
        declined.isDeclined = true
        input.calendarEvents = [
            declined, IslandFixtures.event("allDay", startsIn: -100, endsIn: 5, allDay: true),
            IslandFixtures.event("later", startsIn: -100, endsIn: 100), expected,
        ]
        #expect(build(input).first?.detail == .inProgress(expected))
    }

    @Test func timersIncludePausedAndOverrunWhenAnyTimerRuns() {
        var input = IslandInput()
        var paused = CountdownTimer(title: "Paused", duration: 60, start: now)
        paused.togglePause(at: now)
        let overrun = CountdownTimer(title: "Overrun", duration: 60, start: now.addingTimeInterval(-100))
        input.timers = [paused]
        #expect(build(input).isEmpty)
        input.timers.append(overrun)
        let events = build(input)
        #expect(events.count == 1)
        #expect(events.first?.detail == .timers(input.timers))
        #expect(events.first?.expires == nil)
        #expect(overrun.endDate?.timeIntervalSince(now) == -40)
    }

    @Test func runningTimerProducesOngoingEvent() {
        var input = IslandInput()
        input.timers = [CountdownTimer(title: "Tea", duration: 60, start: now)]
        #expect(build(input).first?.id == "timers")
        #expect(build(input).first?.expires == nil)
    }

    @Test(arguments: [(79.999, false), (80.0, true), (80.001, true)])
    func temperatureUsesUserThresholdAndCPUAverage(average: Double, expected: Bool) {
        var input = IslandInput()
        input.alerts.highTemperature = 80
        input.sensors = SensorSample(readings: [
            SensorReading(key: "Tp", group: .cpuPerformance, celsius: average - 5),
            SensorReading(key: "Te", group: .cpuEfficiency, celsius: average + 5),
            SensorReading(key: "Tg", group: .gpu, celsius: 120),
        ], fans: [])
        input.processes = [
            ProcessUsage(pid: 1, name: "Low", cpu: 10, memory: 0),
            ProcessUsage(pid: 2, name: "High", cpu: 80, memory: 0),
        ]
        let events = build(input)
        #expect(!events.isEmpty == expected)
        if expected {
            #expect(events.first?.detail == .systemAlert(IslandSystemAlert(
                averageCPU: average, topProcess: input.processes[1], lowSpaceVolume: nil
            )))
        }
    }

    @Test(arguments: [(9_999_999_999 as UInt64, true), (10_000_000_000, false), (10_000_000_001, false)])
    func lowDiskSpaceUsesStartupVolume(free: UInt64, expected: Bool) {
        var input = IslandInput()
        input.volumes = [IslandFixtures.volume(path: "/Volumes/Other", free: 0), IslandFixtures.volume(free: free)]
        #expect(build(input).contains { $0.kind == .systemAlert } == expected)
    }

    @Test func diskThresholdCanBeOverriddenAndCombinesWithTemperature() {
        var input = IslandInput()
        input.lowSpaceBytes = 100
        input.volumes = [IslandFixtures.volume(free: 99)]
        input.sensors = SensorSample(
            readings: [SensorReading(key: "Tp", group: .cpuPerformance, celsius: 100)],
            fans: []
        )
        let events = build(input)
        #expect(events.count == 1)
        #expect(events.first?.detail == .systemAlert(IslandSystemAlert(
            averageCPU: 100, topProcess: nil, lowSpaceVolume: input.volumes[0]
        )))
    }

    @Test func networkLossRequiresKnownConnectedPreviousReading() {
        var previous = IslandInput()
        previous.wifi = IslandFixtures.wifi
        previous.vpn = IslandFixtures.vpn
        var current = previous
        current.wifi = .off
        current.vpn = IslandFixtures.vpnOff
        #expect(build(current).isEmpty)
        let events = build(current, previous: previous)
        #expect(events.map(\.id) == ["wifi", "vpn"])
        #expect(events.allSatisfy { $0.expires == nil })
        #expect(events[0].detail == .network(.wifiLost(.off)))
        #expect(events[1].detail == .network(.vpnOff(IslandFixtures.vpnOff)))
        #expect(build(current, previous: current).isEmpty)
        #expect(build(previous, previous: current).isEmpty)
        #expect(build(IslandInput(), previous: previous).isEmpty)
    }

    @Test(arguments: [PingOutcome.timeout, .offline, .unresolved, .reply(milliseconds: 300.001)])
    func pingRecoveryIsTransient(bad: PingOutcome) {
        var previous = IslandInput()
        previous.ping = bad
        var current = previous
        current.ping = .reply(milliseconds: 300)
        let events = build(current, previous: previous)
        #expect(events.first?.detail == .network(.pingRecovered(.reply(milliseconds: 300))))
        #expect(events.first?.expires == now.addingTimeInterval(4))
        #expect(build(current, previous: current).isEmpty)
        #expect(build(previous, previous: current).isEmpty)
    }

    @Test func containerExitPersistsAndServerAppearanceExpires() {
        var previous = IslandInput()
        previous.docker = .containers([IslandFixtures.container(running: true)], context: nil)
        previous.devServers = .servers([])
        var current = previous
        let exited = IslandFixtures.container(running: false)
        let server = IslandFixtures.server()
        current.docker = .containers([exited], context: nil)
        current.devServers = .servers([server])
        let events = build(current, previous: previous)
        #expect(events.map(\.id) == ["container:db", "server:42:3000"])
        #expect(events[0].detail == .devServers(.containerExited(exited)))
        #expect(events[0].expires == nil)
        #expect(events[1].detail == .devServers(.serverAppeared(server)))
        #expect(events[1].expires == now.addingTimeInterval(4))
        #expect(build(current, previous: current).isEmpty)
        #expect(build(current).isEmpty)
    }

    @Test func collectorFailuresAreNotExitOrAppearanceTransitions() {
        var previous = IslandInput()
        previous.docker = .containers([IslandFixtures.container(running: true)], context: nil)
        previous.devServers = .failed
        var current = previous
        current.docker = .failed("Unavailable")
        current.devServers = .servers([IslandFixtures.server()])
        #expect(build(current, previous: previous).isEmpty)
    }

    @Test func pausedOrRestartingContainersAreNotExited() {
        var previous = IslandInput()
        previous.docker = .containers([IslandFixtures.container(running: true)], context: nil)
        for status in ["Up 1 hour (Paused)", "Restarting (1) 2 seconds ago", "Created"] {
            var current = previous
            current.docker = .containers([DockerContainer(
                id: "db", name: "database", image: "postgres", status: status, isRunning: false, ports: []
            )], context: nil)
            #expect(build(current, previous: previous).isEmpty)
        }
    }

    @Test func serverRestartWithNewPIDCountsAsAppearance() {
        var previous = IslandInput()
        previous.devServers = .servers([IslandFixtures.server()])
        var current = previous
        current.devServers = .servers([IslandFixtures.server(pid: 43)])
        #expect(build(current, previous: previous).first?.id == "server:43:3000")
    }

    @Test func adapterConnectionIsTransientEvenIfBatteryIsFull() {
        var previous = IslandInput()
        previous.battery = IslandFixtures.battery(onAC: false)
        var current = previous
        current.battery = IslandFixtures.battery(onAC: true)
        current.battery?.isCharging = false
        current.battery?.charge = 1
        let events = build(current, previous: previous)
        #expect(events.first?.kind == .charging)
        #expect(events.first?.expires == now.addingTimeInterval(4))
        #expect(build(current).isEmpty)
        #expect(build(current, previous: current).isEmpty)
        #expect(build(previous, previous: current).isEmpty)
    }

    @Test func keepAwakeRequiresOwnModeAndFutureEnd() {
        var input = IslandInput()
        input.keepAwakeEnds = now.addingTimeInterval(60)
        #expect(build(input).isEmpty)
        input.isKeepingAwake = true
        #expect(build(input).first?.detail == .keepAwake(endsAt: now.addingTimeInterval(60)))
        input.keepAwakeEnds = now
        #expect(build(input).isEmpty)
        input.keepAwakeEnds = nil
        #expect(build(input).isEmpty)
    }

    @Test func nowPlayingRequiresPlayback() {
        var input = IslandInput()
        input.nowPlaying = NowPlayingSession(track: NowPlayingTrack(title: "Song"), isPlaying: false)
        #expect(build(input).isEmpty)
        input.nowPlaying?.isPlaying = true
        #expect(build(input).first?.detail == input.nowPlaying.map(IslandDetail.nowPlaying))
        #expect(build(input).first?.expires == nil)
    }

    @Test func clipboardUsesNewestIdentityAndExpires() {
        var current = IslandInput()
        current.clipboardEntry = IslandFixtures.clipboard()
        #expect(build(current).isEmpty)
        let events = build(current, previous: IslandInput())
        #expect(events.first?.detail == current.clipboardEntry.map(IslandDetail.copied))
        #expect(events.first?.expires == now.addingTimeInterval(4))
        #expect(build(current, previous: current).isEmpty)
        var next = current
        next.clipboardEntry = IslandFixtures.clipboard()
        #expect(build(next, previous: current).first?.kind == .copied)
        #expect(build(IslandInput(), previous: next).isEmpty)
    }

    @Test func reservedAndUnsupportedKindsAreNotProduced() {
        let events = build(IslandInput(), previous: IslandInput())
        let unsupported: Set<IslandEventKind> = [.downloads, .airPods, .volume, .agents]
        #expect(events.allSatisfy { !unsupported.contains($0.kind) })
    }

    private func build(_ input: IslandInput, previous: IslandInput? = nil) -> [IslandEvent] {
        IslandEventBuilder.events(current: input, previous: previous, now: now)
    }
}
