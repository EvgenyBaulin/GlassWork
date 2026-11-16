import AppKit
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

@MainActor
struct MenuBarStateItemTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func timer(_ seconds: Double, paused: Bool = false) -> CountdownTimer {
        var timer = CountdownTimer(title: "T", duration: seconds, start: now)
        if paused {
            timer.togglePause(at: now)
        }
        return timer
    }

    @Test func oneTimerShowsNoCount() {
        let item = ItemContent.timers([timer(252)], at: now, options: [:])
        #expect(item.figure == "4:12")
        #expect(!item.isDimmed)
    }

    @Test func severalTimersShowTheCountAndTheSoonest() {
        let item = ItemContent.timers([timer(900), timer(252)], at: now, options: [:])
        #expect(item.figure == "2 · 4:12")
        #expect(item.template.hasPrefix("2 · "))
    }

    @Test func aPausedTimerDimsTheItem() {
        let item = ItemContent.timers([timer(252, paused: true)], at: now, options: [:])
        #expect(item.figure == "4:12")
        #expect(item.isDimmed)
        #expect(item.symbol == "pause.circle")
    }

    @Test func aRunningTimerCountsBeforeAPausedOne() {
        let item = ItemContent.timers([timer(60, paused: true), timer(900)], at: now, options: [:])
        #expect(item.figure == "2 · 15:00")
        #expect(!item.isDimmed)
    }

    @Test func noTimersShowADash() {
        #expect(ItemContent.timers([], at: now, options: [:]).figure == "—")
    }

    @Test func twoCitiesAreAnOption() {
        let cities = [
            WorldCity(name: "Moscow", timeZone: "Europe/Moscow"),
            WorldCity(name: "Tokyo", timeZone: "Asia/Tokyo"),
        ]
        let one = ItemContent.worldClocks(cities, at: now, options: [:])
        let two = ItemContent.worldClocks(cities, at: now, options: [ItemOption.showsTwoCities: "true"])
        #expect(!one.figure.contains("·"))
        #expect(two.figure.split(separator: "·").count == 2)
        #expect(two.template.count > one.template.count)
    }

    @Test func noCitiesShowADash() {
        #expect(ItemContent.worldClocks([], at: now, options: [:]).figure == "—")
    }

    @Test func offsetsReadAsHours() {
        #expect(WorldClockOffset.text(3 * 3600) == "+3 h")
        #expect(WorldClockOffset.text(-8 * 3600) == "−8 h")
        #expect(WorldClockOffset.text(5 * 3600 + 1800) == "+5:30 h")
        #expect(WorldClockOffset.text(-(9 * 3600 + 1800)) == "−9:30 h")
        #expect(WorldClockOffset.text(0) == "Same time")
    }

    @Test func calendarTextsFollowTheState() {
        let standup = AgendaEvent(id: "1", title: "Standup", start: now, end: now)
        #expect(ItemContent.calendarText(.upcoming(standup, startsIn: 1500), limit: 20) == "in 25 min · Standup")
        #expect(ItemContent.calendarText(.current(standup, endsIn: 900), limit: 20) == "now · Standup, 15 min left")
        #expect(ItemContent.calendarText(.callSoon(standup), limit: 20) == "Join · Standup")
        #expect(ItemContent.span(1) == "1 min")
        #expect(ItemContent.span(7200) == "2 h")
    }

    @Test func calendarTemplateCoversEveryForm() {
        let standup = AgendaEvent(
            id: "1",
            title: "Standup",
            start: now.addingTimeInterval(1500),
            end: now.addingTimeInterval(3000)
        )
        let item = ItemContent.calendar([standup], at: now, options: [ItemOption.titleLength: "20"])
        #expect(item.figure == "in 25 min · Standup")
        #expect(item.template.count >= "now · , 59 min left".count + 20)
    }

    private func volume(_ name: String) -> DiskVolume {
        DiskVolume(name: name, path: "/Volumes/\(name)", total: 100, free: 50, isInternal: false, isEjectable: true)
    }

    @Test func noVolumesHideTheEjectItem() {
        let item = ItemContent.eject([], ejecting: [], failures: [:], options: [:])
        #expect(item.isHidden)
        let shown = ItemContent.eject(
            [], ejecting: [], failures: [:], options: [ItemOption.ejectHidesWhenEmpty: "false"]
        )
        #expect(!shown.isHidden)
        #expect(shown.isDimmed)
    }

    @Test func theEjectItemCountsVolumes() {
        let item = ItemContent.eject([volume("A"), volume("B")], ejecting: [], failures: [:], options: [:])
        #expect(item.figure == "2")
        #expect(!item.isHidden)
    }

    @Test func theEjectItemShowsAnEjectInProgress() {
        let item = ItemContent.eject([volume("A")], ejecting: ["/Volumes/A"], failures: [:], options: [:])
        #expect(item.figure == "Ejecting…")
        #expect(item.template == "Ejecting…")
    }

    @Test func theEjectItemKeepsTheRefusal() {
        let item = ItemContent.eject(
            [volume("A")], ejecting: [], failures: ["/Volumes/A": "In use by Finder"], options: [:]
        )
        #expect(item.symbol == "exclamationmark.triangle")
        #expect(item.detail == "A: In use by Finder")
    }

    @Test func aDissentingProgramIsNamed() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: 1,
            userInfo: [NSFileManagerUnmountDissentingProcessIdentifierErrorKey: 321]
        )
        #expect(EjectFailure.message(for: error) { $0 == 321 ? "Finder" : nil } == "In use by Finder")
        #expect(EjectFailure.message(for: error) { _ in nil } == "Could not eject")
        #expect(EjectFailure.message(for: NSError(domain: NSCocoaErrorDomain, code: 1)) { _ in
            "x"
        } == "Could not eject")
    }
}
