import Foundation
@testable import GlassWorkCore
import Testing

struct DockWidgetClickTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func resolve(_ module: ModuleID, _ context: DockWidgetContext = DockWidgetContext()) -> DockWidgetClick {
        DockWidgetClick.resolve(module, context: context, at: now)
    }

    private func event(startsIn seconds: Double, lasting: Double = 1800, call: String?) -> AgendaEvent {
        var event = AgendaEvent(
            id: UUID().uuidString,
            title: "Sync",
            start: now.addingTimeInterval(seconds),
            end: now.addingTimeInterval(seconds + lasting),
            isAllDay: false
        )
        event.callURL = call.flatMap(URL.init(string:))
        return event
    }

    @Test func aTimerClickStartsTwentyFiveMinutes() {
        #expect(resolve(.timers) == .perform(.startTimer(seconds: 1500)))
    }

    @Test func aTimerClickPausesTheOneRunning() {
        let timer = CountdownTimer(title: "Tea", duration: 60, start: now)
        #expect(resolve(.timers, DockWidgetContext(timers: [timer])) == .perform(.toggleTimer(timer.id)))
    }

    @Test func switchesFlipOnClick() {
        #expect(resolve(.stopwatch) == .toggleStopwatch)
        #expect(resolve(.keepAwake) == .toggleKeepAwake)
        #expect(resolve(.nowPlaying) == .togglePlayback)
    }

    @Test func devServersOpenTheFirstWebServer() throws {
        let database = DevServer(port: 5432, pid: 1, process: "postgres", project: "api", kind: .service)
        let web = DevServer(port: 3000, pid: 2, process: "node", project: "site", kind: .web)
        let context = DockWidgetContext(devServers: .servers([database, web]))
        #expect(try resolve(.devServers, context) == .open(#require(URL(string: "http://localhost:3000"))))
    }

    @Test func devServersWithNothingToOpenShowTheCard() {
        let database = DevServer(port: 5432, pid: 1, process: "postgres", project: "api", kind: .service)
        #expect(resolve(.devServers, DockWidgetContext(devServers: .servers([database]))) == .showCard)
        #expect(resolve(.devServers) == .showCard)
    }

    @Test func aCallAboutToStartIsJoinedInOneClick() throws {
        let link = "https://example.com/call"
        let context = DockWidgetContext(events: [event(startsIn: 240, call: link)])
        #expect(try resolve(.calendar, context) == .open(#require(URL(string: link))))
    }

    @Test func aCallUnderWayCanStillBeJoined() throws {
        let link = "https://example.com/call"
        let context = DockWidgetContext(events: [event(startsIn: -600, call: link)])
        #expect(try resolve(.endsIn, context) == .open(#require(URL(string: link))))
    }

    @Test func aDistantCallOrPlainEventShowsTheCard() {
        #expect(resolve(.calendar, DockWidgetContext(events: [event(startsIn: 3600, call: "https://a.example")])) ==
            .showCard)
        #expect(resolve(.calendar, DockWidgetContext(events: [event(startsIn: 60, call: nil)])) == .showCard)
    }

    @Test func aFinishedOrDeclinedCallIsNotJoined() {
        var declined = event(startsIn: 60, call: "https://a.example")
        declined.isDeclined = true
        let finished = event(startsIn: -7200, call: "https://a.example")
        #expect(resolve(.calendar, DockWidgetContext(events: [declined, finished])) == .showCard)
    }

    /// Nothing that writes to the system may hide behind a click. Containers stay read-only too.
    @Test func everyOtherWidgetOnlyShowsItsCard() {
        let acting: Set<ModuleID> = [.timers, .stopwatch, .keepAwake, .nowPlaying]
        for module in ModuleID.allCases where !acting.contains(module) {
            #expect(resolve(module) == .showCard)
        }
    }

    @Test func aSwitchHasNoCardToOpen() {
        #expect(!ModuleID.stopwatch.hasDockCard)
        #expect(!ModuleID.keepAwake.hasDockCard)
        #expect(ModuleID.battery.hasDockCard)
    }

    @Test func modulesWithNothingToShowAreNotOffered() {
        #expect(!ModuleID.dockWidgets.contains(.shelf))
        #expect(!ModuleID.dockWidgets.contains(.appearance))
        #expect(ModuleID.dockWidgets.contains(.timers))
    }
}

struct DockPressTests {
    @Test func aQuickPressIsAClick() {
        var press = DockPress()
        let isClick = press.released()
        #expect(isClick)
    }

    @Test func aHoldIsNotAlsoAClick() {
        var press = DockPress()
        press.held()
        let isClick = press.released()
        #expect(!isClick)
    }

    @Test func theClickAfterAHoldCounts() {
        var press = DockPress()
        press.held()
        _ = press.released()
        let isClick = press.released()
        #expect(isClick)
    }

    /// A release outside the tile never reaches the button, so nothing else would clear the hold.
    @Test func aHoldReleasedOutsideDoesNotSwallowTheNextClick() {
        var press = DockPress()
        press.held()
        press.left()
        let isClick = press.released()
        #expect(isClick)
    }
}

struct DockCardFrameTests {
    private let visible = CGRect(x: 0, y: 75, width: 1512, height: 875)
    private let size = CGSize(width: 340, height: 400)

    private func settings(_ position: DockPosition, magnifies: Bool = true) -> DockSettings {
        var settings = DockSettings()
        settings.iconSize = 48
        settings.magnifiedSize = 80
        settings.magnifies = magnifies
        settings.position = position
        return settings
    }

    private func frame(_ position: DockPosition, pointer: CGPoint, bar: CGRect) -> CGRect {
        DockBarLayout.cardFrame(size: size, pointer: pointer, bar: bar, settings: settings(position), visible: visible)
    }

    @Test func standsAboveTheTileClearOfMagnifiedIcons() {
        let bar = CGRect(x: 600, y: 4, width: 300, height: 71)
        let card = frame(.bottom, pointer: CGPoint(x: 700, y: 30), bar: bar)
        #expect(card == CGRect(x: 530, y: 117, width: 340, height: 400))
    }

    @Test func comesCloserWithoutMagnification() {
        let bar = CGRect(x: 600, y: 4, width: 300, height: 71)
        let card = DockBarLayout.cardFrame(
            size: size,
            pointer: CGPoint(x: 700, y: 30),
            bar: bar,
            settings: settings(.bottom, magnifies: false),
            visible: visible
        )
        #expect(card.minY == 85)
    }

    @Test func staysOnScreenAtTheEnds() {
        let bar = CGRect(x: 0, y: 4, width: 1512, height: 71)
        #expect(frame(.bottom, pointer: CGPoint(x: 10, y: 30), bar: bar).minX == 8)
        #expect(frame(.bottom, pointer: CGPoint(x: 1505, y: 30), bar: bar).minX == 1164)
    }

    @Test func standsBesideASideDock() {
        let left = CGRect(x: 4, y: 300, width: 71, height: 300)
        let right = CGRect(x: 1437, y: 300, width: 71, height: 300)
        #expect(frame(.left, pointer: CGPoint(x: 30, y: 400), bar: left).minX == 117)
        #expect(frame(.right, pointer: CGPoint(x: 1480, y: 400), bar: right).minX == 1055)
    }

    @Test func aSideCardStaysBelowTheMenuBar() {
        let left = CGRect(x: 4, y: 300, width: 71, height: 600)
        #expect(frame(.left, pointer: CGPoint(x: 30, y: 940), bar: left).minY == 542)
    }

    @Test func aCardTallerThanTheScreenKeepsItsBottomOnScreen() {
        let card = DockBarLayout.cardFrame(
            size: CGSize(width: 340, height: 2000),
            pointer: CGPoint(x: 30, y: 400),
            bar: CGRect(x: 4, y: 300, width: 71, height: 300),
            settings: settings(.left),
            visible: visible
        )
        #expect(card.minY == 83)
    }
}

struct DockWidgetListTests {
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")

    @Test func aDockThatIsOffReadsNothing() {
        var dock = DockSettings()
        dock.items = [.widget(.cpu)]
        #expect(dock.shownWidgets.isEmpty)
        dock.isEnabled = true
        #expect(dock.shownWidgets == [.cpu])
    }

    /// Reading devices may raise a Bluetooth prompt, so a hand-edited tile must not start it.
    @Test func aWidgetTheDockDoesNotOfferStartsNoRead() {
        var dock = DockSettings()
        dock.isEnabled = true
        dock.items = [.widget(.deviceBatteries), .widget(.battery)]
        #expect(dock.shownWidgets == [.battery])
    }

    @Test func settingWidgetsKeepsAppsAndDropsDuplicates() {
        let items: [DockItem] = [.widget(.cpu), .app(mail), .widget(.memory)]
        let result = DockLayout.setting(widgets: [.memory, .battery, .memory], in: items)
        #expect(result == [.app(mail), .widget(.memory), .widget(.battery)])
    }

    @Test func removingLeavesTheRest() {
        let items: [DockItem] = [.app(mail), .widget(.cpu)]
        #expect(DockLayout.removing(.widget(.cpu), from: items) == [.app(mail)])
    }
}
