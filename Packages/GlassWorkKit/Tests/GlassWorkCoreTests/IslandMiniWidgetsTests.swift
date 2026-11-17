import Foundation
@testable import GlassWorkCore
import Testing

struct IslandMiniWidgetsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func defaultSetMatchesTheDesign() {
        #expect(IslandMiniSet().shown == [.upNext, .weather, .rates])
        #expect(IslandMiniSet().hidden == [.cpu, .memory, .battery])
    }

    @Test func toggleAddsAtTheEndAndRemoves() {
        var set = IslandMiniSet()
        set.toggle(.cpu)
        #expect(set.shown == [.upNext, .weather, .rates, .cpu])
        set.toggle(.weather)
        #expect(set.shown == [.upNext, .rates, .cpu])
        #expect(!set.contains(.weather))
    }

    @Test func moveSwapsNeighboursAndStopsAtTheEnds() {
        var set = IslandMiniSet()
        set.move(.rates, by: -1)
        #expect(set.shown == [.upNext, .rates, .weather])
        set.move(.upNext, by: -1)
        set.move(.weather, by: 1)
        #expect(set.shown == [.upNext, .rates, .weather])
    }

    @Test func unknownIDsSurviveARoundTripAndAreNotShown() throws {
        let set = try JSONDecoder().decode(IslandMiniSet.self, from: Data(#"["cpu","futureThing","cpu"]"#.utf8))
        #expect(set.shown == [.cpu])
        let again = try JSONDecoder().decode(IslandMiniSet.self, from: JSONEncoder().encode(set))
        #expect(again.ids == ["cpu", "futureThing", "cpu"])
    }

    @Test func settingsWithoutTheKeyGetTheDefault() throws {
        let settings = try JSONDecoder().decode(IslandSettings.self, from: Data(#"{"isEnabled":false}"#.utf8))
        #expect(settings.miniWidgets == IslandMiniSet())
        #expect(!settings.isEnabled)
    }

    @Test func settingsKeepAChosenSet() throws {
        var settings = IslandSettings()
        settings.miniWidgets.toggle(.battery)
        let decoded = try JSONDecoder().decode(IslandSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.miniWidgets.shown == [.upNext, .weather, .rates, .battery])
    }

    @Test func onlyReadingsWithDataExist() {
        #expect(IslandMiniReading.readings(from: IslandInput(), now: now).isEmpty)
        var input = IslandInput()
        input.battery = IslandFixtures.battery(onAC: false)
        input.calendarEvents = [IslandFixtures.event(startsIn: 3600, endsIn: 7200)]
        let readings = IslandMiniReading.readings(from: input, now: now)
        #expect(Set(readings.keys) == [.battery, .upNext])
        #expect(readings[.battery]?.value == Format.percent(0.5))
        #expect(readings[.upNext]?.detail == "Planning")
        #expect(readings[.upNext]?.date == now.addingTimeInterval(3600))
    }

    @Test func ratesUseTheFirstTwoPairs() {
        var input = IslandInput()
        input.rates = [
            RateQuote(
                pair: RatePair(base: "USD", quote: "RUB"), source: .cbr, value: 92.4, change: 0, history: [], date: now
            ),
            RateQuote(
                pair: RatePair(base: "EUR", quote: "RUB"), source: .cbr, value: 99.12, change: 0, history: [], date: now
            ),
        ]
        let reading = IslandMiniReading.readings(from: input, now: now)[.rates]
        #expect(reading?.value.hasPrefix("USD ") == true)
        #expect(reading?.detail.hasPrefix("EUR ") == true)
    }

    @Test func clickingThePeekOpensTheCardOnlyWhenAsked() {
        var state = IslandLifecycle()
        state.clicked()
        state.clicked()
        #expect(state.phase == .peek)
        state.opensWidgets = true
        state.clicked()
        #expect(state.phase == .expanded)
        state.clickedOutside()
        #expect(state.phase == .idle)
    }
}
