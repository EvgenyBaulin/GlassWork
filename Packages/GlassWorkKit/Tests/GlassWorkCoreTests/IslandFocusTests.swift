import Foundation
@testable import GlassWorkCore
import Testing

struct IslandFocusTests {
    private let now = IslandFixtures.now
    private let sleep = FocusReading(
        isOn: true, modeID: "com.apple.sleep.sleep-mode", name: "Sleep", symbol: "bed.double.fill"
    )
    private let work = FocusReading(
        isOn: true, modeID: "com.apple.focus.work", name: "Work", symbol: "person.lanyardcard.fill"
    )
    private let off = FocusReading(isOn: false)

    private func input(_ focus: FocusReading?) -> IslandInput {
        var input = IslandInput()
        input.focus = focus
        return input
    }

    // MARK: Parser

    @Test func activeAssertionGivesTheModeNameAndSymbol() throws {
        let reading = try FocusFiles.parse(
            assertions: fixture("focus-assertions-on.json"),
            configurations: fixture("focus-mode-configurations.json")
        )
        #expect(reading == sleep)
    }

    @Test func noAssertionsMeansOff() throws {
        let reading = try FocusFiles.parse(
            assertions: fixture("focus-assertions-off.json"),
            configurations: fixture("focus-mode-configurations.json")
        )
        #expect(reading == off)
    }

    @Test func missingConfigurationsLeaveTheNameEmpty() throws {
        let reading = try FocusFiles.parse(assertions: fixture("focus-assertions-on.json"), configurations: nil)
        #expect(reading == FocusReading(isOn: true, modeID: "com.apple.sleep.sleep-mode"))
    }

    @Test func unknownModeLeavesTheNameEmpty() throws {
        let reading = try FocusFiles.parse(
            assertions: fixture("focus-assertions-on.json"),
            configurations: Data(#"{"data":[{"modeConfigurations":{}}]}"#.utf8)
        )
        #expect(reading?.isOn == true)
        #expect(reading?.name == nil)
    }

    @Test func unreadableFilesGiveNoReading() {
        #expect(FocusFiles.parse(assertions: Data("not json".utf8), configurations: nil) == nil)
        #expect(FocusFiles.parse(assertions: Data(#"{"data":[]}"#.utf8), configurations: nil) == nil)
    }

    @Test func theLatestAssertionWins() {
        let assertions = Data("""
        {"data":[{"storeAssertionRecords":[
        {"assertionStartDateTimestamp":10,"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}},
        {"assertionStartDateTimestamp":20,"assertionDetails":{"assertionDetailsModeIdentifier":"a.b"}}]}]}
        """.utf8)
        #expect(FocusFiles.parse(assertions: assertions, configurations: nil)?.modeID == "a.b")
    }

    @Test func readsBothFilesFromAFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "focus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try fixture("focus-assertions-on.json").write(to: folder.appending(path: FocusFiles.assertionsName))
        try fixture("focus-mode-configurations.json").write(to: folder.appending(path: FocusFiles.configurationsName))
        #expect(FocusFiles.read(in: folder) == sleep)
        #expect(FocusFiles.modificationDate(in: folder) != nil)
        #expect(FocusFiles.read(in: folder.appending(path: "missing")) == nil)
    }

    // MARK: Events

    @Test func turningOnShowsTheModeOnce() throws {
        let events = IslandEventBuilder.events(current: input(work), previous: input(off), now: now)
        #expect(events.map(\.kind) == [.focus])
        let event = try #require(events.first)
        #expect(event.detail == .focus(work))
        #expect(event.expires != nil)
        let again = IslandEventBuilder.events(current: input(work), previous: input(work), now: now)
        #expect(again.isEmpty)
    }

    @Test func turningOffNamesTheModeThatEnded() throws {
        let events = IslandEventBuilder.events(current: input(off), previous: input(sleep), now: now)
        let event = try #require(events.first)
        #expect(event.detail == .focus(FocusReading(
            isOn: false, modeID: sleep.modeID, name: "Sleep", symbol: "bed.double.fill"
        )))
    }

    @Test func switchingModesShowsTheNewOne() {
        let events = IslandEventBuilder.events(current: input(work), previous: input(sleep), now: now)
        #expect(events.first?.detail == .focus(work))
    }

    @Test func startupAndUnreadableFilesShowNothing() {
        #expect(IslandEventBuilder.events(current: input(work), previous: nil, now: now).isEmpty)
        #expect(IslandEventBuilder.events(current: input(work), previous: input(nil), now: now).isEmpty)
        #expect(IslandEventBuilder.events(current: input(nil), previous: input(work), now: now).isEmpty)
    }
}
