import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetCommandTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeInbox() -> WidgetCommandInbox {
        WidgetCommandInbox(directory: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkCommands-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func aFreshCommandComesThroughOnce() throws {
        let inbox = makeInbox()
        try inbox.send(WidgetCommand(issuedAt: date, action: .toggleFanMax))

        #expect(inbox.drain(at: date.addingTimeInterval(1)).map(\.action) == [.toggleFanMax])
        #expect(inbox.drain(at: date.addingTimeInterval(1)).isEmpty)
    }

    /// A Max tapped while the app was closed must not start the fans on the next launch.
    @Test func aStaleCommandIsDroppedAndDeleted() throws {
        let inbox = makeInbox()
        try inbox.send(WidgetCommand(issuedAt: date, action: .toggleFanMax))

        #expect(inbox.drain(at: date.addingTimeInterval(WidgetCommandInbox.maxAge + 1)).isEmpty)
        #expect(inbox.drain(at: date).isEmpty)
    }

    @Test func aCommandFromTheFutureIsDropped() throws {
        let inbox = makeInbox()
        try inbox.send(WidgetCommand(issuedAt: date.addingTimeInterval(3600), action: .toggleFanMax))
        #expect(inbox.drain(at: date).isEmpty)
    }

    @Test func aBrokenFileIsRemovedAndIgnored() throws {
        let inbox = makeInbox()
        try inbox.send(WidgetCommand(issuedAt: date, action: .toggleFanMax))
        try Data("not json".utf8).write(to: inbox.directory.appending(path: "broken.json"))

        #expect(inbox.drain(at: date).count == 1)
        let left = try FileManager.default.contentsOfDirectory(atPath: inbox.directory.path())
        #expect(left.isEmpty)
    }

    @Test func commandsComeOldestFirst() throws {
        let inbox = makeInbox()
        try inbox.send(WidgetCommand(issuedAt: date.addingTimeInterval(2), action: .setFanMode(.auto)))
        try inbox.send(WidgetCommand(issuedAt: date, action: .setFanMode(.max)))

        #expect(inbox.drain(at: date).map(\.action) == [.setFanMode(.max), .setFanMode(.auto)])
    }

    @Test func anEmptyInboxIsFine() {
        #expect(makeInbox().drain(at: date).isEmpty)
    }

    @Test(arguments: [
        WidgetCommand.Action.toggleFanMax,
        .setFanMode(.curve),
        .selectFanPreset("silent"),
        .setFanCustom(rpm: 3000),
        .setTodo(id: "abc", completed: true),
        .startTimer(seconds: 300),
        .toggleTimer(UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()),
        .eject(path: "/Volumes/Backup"),
        .runCommand(UUID(uuidString: "00000000-0000-0000-0000-000000000002") ?? UUID()),
    ])
    func survivesTheTripThroughAnIntentParameter(action: WidgetCommand.Action) {
        #expect(WidgetCommand.Action(encoded: action.encoded) == action)
    }

    @Test func nonsenseFromAnIntentIsRefused() {
        #expect(WidgetCommand.Action(encoded: "{}") == nil)
        #expect(WidgetCommand.Action(encoded: "") == nil)
    }

    @Test func theSignalNameIsNeverEmpty() {
        #expect(WidgetCommandSignal.name.hasSuffix(".widget-command"))
    }

    @Test func onlyFanActionsCountAsFanActions() {
        #expect(WidgetCommand.Action.toggleFanMax.isFanAction)
        #expect(WidgetCommand.Action.startTimer(seconds: 60).isFanAction == false)
    }
}

@MainActor
struct WidgetDemandTests {
    @Test func aWidgetReadsOnlyWhatItShows() {
        let demand = MonitorDemand(widgets: [.network])
        #expect(demand.network)
        #expect(demand.cpu == false)
        #expect(demand.processes == false)
        #expect(demand.slowProcesses == false)
    }

    @Test func clocksReadNothing() {
        #expect(MonitorDemand(widgets: [.clock, .moon]).readsSamples == false)
    }

    @Test func developerWidgetsTurnOnTheirModules() {
        let demand = MonitorDemand(widgets: [.git, .containers, .wifiSignal, .aiUsage])
        #expect(demand.developer == [.git, .docker, .wifi, .aiUsage])
    }

    @Test func topAppsNeverRunsPsOnEveryTick() {
        let demand = MonitorDemand(widgets: [.topApps])
        #expect(demand.slowProcesses)
        #expect(demand.processes == false)
    }

    @Test func subtractingLeavesOnlyWhatIsNotReadYet() {
        var live = MonitorDemand()
        live.cpu = true
        live.processes = true
        let rest = MonitorDemand(widgets: [.activity]).subtracting(live)
        #expect(rest.cpu == false)
        #expect(rest.memory)
        #expect(rest.gpu)
        #expect(rest.slowProcesses == false)
    }

    @Test func snapshotCarriesOnlyWhatPlacedWidgetsShow() {
        let monitor = SystemMonitor()
        let snapshot = monitor.widgetSnapshot(for: [.clock])
        #expect(snapshot.weather == nil)
        #expect(snapshot.rates == nil)
        #expect(snapshot.git == nil)
        #expect(snapshot.wifiHistory == nil)
        #expect(snapshot.diskMinute == nil)
        #expect(snapshot.fanHistory == nil)
    }

    /// Before the first read the list is empty, which must not reach the widget as "no devices".
    @Test func devicesStayUnknownUntilTheFirstRead() {
        #expect(SystemMonitor().widgetSnapshot(for: [.devices]).devices == nil)
    }

    @Test func weatherTellsNoPlaceFromNoForecastYet() {
        #expect(SystemMonitor().widgetSnapshot(for: [.weather]).weather?.hasPlaces == false)
    }

    @Test func snapshotCarriesTheForecastForTheWeatherWidget() {
        let monitor = SystemMonitor()
        #expect(monitor.widgetSnapshot(for: [.weather]).weather != nil)
        #expect(monitor.widgetSnapshot(for: [.rates]).rates != nil)
    }

    /// Takes a snapshot from before these widgets, which the extension may read until the next refresh.
    @Test func olderSnapshotStillDecodes() throws {
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkOld-\(UUID().uuidString)", directoryHint: .isDirectory))
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.fans = nil
        try store.write(snapshot, for: WidgetSnapshot.key)

        let read = try #require(store.read(WidgetSnapshot.self, for: WidgetSnapshot.key))

        #expect(read.fans == nil)
        #expect(read.git == nil)
    }

    @Test func readingsSurviveTheSharedStore() throws {
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkReadings-\(UUID().uuidString)", directoryHint: .isDirectory))
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        var status = GitStatus()
        status.branch = "main"
        status.changed = 2
        snapshot.git = .repositories([GitRepository(path: "/tmp/a", status: status)])
        snapshot.docker = .containers([
            DockerContainer(
                id: "1", name: "db", image: "postgres", status: "Up", isRunning: true, ports: ["5432→5432"]
            ),
        ], context: "orbstack")
        snapshot.devServers = .servers([DevServer(port: 3000, pid: 1, process: "node", project: "site", kind: .web)])
        snapshot.wifi = .connected(WiFiLink(
            rssi: -54, noise: -92, transmitRate: 866, channel: 149, bandCode: 2, widthCode: 3, phyCode: 6
        ))
        snapshot.wifiHistory = [History<Double>.Point(date: snapshot.date, value: 46)]
        snapshot.devices = [DeviceBattery(name: "Mouse", kind: .mouse, charge: 0.45)]
        snapshot.timeMachine = TimeMachineStatus(
            state: .running(progress: 0.4, secondsLeft: nil),
            destination: "Backup"
        )
        snapshot.fans = WidgetFanState(mode: .max, control: .ready, notice: .returnedToAuto)
        snapshot.fanHistory = [0: [History<Double>.Point(date: snapshot.date, value: 2400)]]

        try store.write(snapshot, for: WidgetSnapshot.key)

        #expect(store.read(WidgetSnapshot.self, for: WidgetSnapshot.key) == snapshot)
    }

    @Test func gitListsWhatNeedsAttentionFirst() {
        func repository(_ name: String, change: (inout GitStatus) -> Void) -> GitRepository {
            var status = GitStatus()
            status.branch = "main"
            change(&status)
            return GitRepository(path: "/tmp/\(name)", status: status)
        }
        let reading = GitReading.repositories([
            repository("clean") { _ in },
            repository("ahead") { $0.ahead = 1 },
            repository("behind") { $0.behind = 1 },
            repository("changed") { $0.changed = 1 },
            GitRepository(path: "/tmp/gone", problem: .missing),
        ])

        #expect(reading.byWork.map(\.name) == ["changed", "behind", "ahead", "clean", "gone"])
        #expect(reading.byWork.count(where: \.needsWork) == 3)
    }
}
