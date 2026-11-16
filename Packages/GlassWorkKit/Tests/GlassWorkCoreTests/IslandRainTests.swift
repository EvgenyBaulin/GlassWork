import Foundation
@testable import GlassWorkCore
import Testing

/// Hours are stamped on the hour, as the forecast stamps them; `IslandFixtures.now` sits on one.
enum RainFixtures {
    static let now = IslandFixtures.now
    static let place = WeatherPlace(id: 1, name: "Moscow", country: "RU", latitude: 55.7, longitude: 37.6)

    /// One entry per amount, the first being the hour under way. Nil means dry with no amount given.
    static func report(
        amounts: [Double?], probability: Double? = 80, condition: WeatherCondition = .rain, at date: Date = now
    ) -> WeatherReport {
        let hours = amounts.enumerated().map { index, amount in
            HourForecast(
                date: date.addingTimeInterval(Double(index) * 3600), temperature: 8,
                condition: amount == nil ? .cloudy : condition, isDay: true, precipitation: amount,
                precipitationProbability: probability
            )
        }
        return WeatherReport(
            place: place, timeZone: "Europe/Moscow", fetchedAt: date,
            current: CurrentWeather(
                temperature: 8, feelsLike: 6, humidity: 80, windSpeed: 3, uvIndex: 0, condition: .cloudy, isDay: true
            ),
            hours: hours, days: []
        )
    }

    static func codeOnly(_ conditions: [WeatherCondition]) -> WeatherReport {
        var report = report(amounts: conditions.map { _ in nil })
        report.hours = conditions.enumerated().map { index, condition in
            HourForecast(
                date: now.addingTimeInterval(Double(index) * 3600), temperature: 8, condition: condition, isDay: true
            )
        }
        return report
    }
}

struct IslandRainTests {
    private let now = RainFixtures.now

    @Test func rainInTheNextHoursStartsAtThatHour() throws {
        let report = RainFixtures.report(amounts: [0, 0, 0.8, 1.2, 0, 0])
        let rain = try #require(IslandRain.reading(from: report, now: now.addingTimeInterval(600)))
        #expect(rain.phase == .starts(now.addingTimeInterval(7200)))
        #expect(rain.start == now.addingTimeInterval(7200))
        #expect(rain.end == now.addingTimeInterval(4 * 3600))
        #expect(rain.peakAmount == 1.2)
        #expect(rain.intensity == .moderate)
        #expect(rain.placeName == "Moscow")
        #expect(rain.hours.map(\.isWet) == [false, false, true, true, false, false])
    }

    @Test func rainFarAwayIsNotWorthAWarning() {
        let report = RainFixtures.report(amounts: [0, 0, 0, 0, 2, 2])
        #expect(IslandRain.reading(from: report, now: now.addingTimeInterval(600)) == nil)
    }

    @Test func rainUnderwayNamesWhenItStops() throws {
        let report = RainFixtures.report(amounts: [0.3, 4.5, 0, 1])
        let rain = try #require(IslandRain.reading(from: report, now: now.addingTimeInterval(1800)))
        #expect(rain.phase == .stops(now.addingTimeInterval(7200)))
        #expect(rain.intensity == .heavy)
        #expect(rain.key == "raining")
    }

    @Test func dryHoursGiveNothing() {
        let report = RainFixtures.report(amounts: [0, 0.05, 0, 0])
        #expect(IslandRain.reading(from: report, now: now) == nil)
    }

    @Test func lowChanceDoesNotCount() {
        let report = RainFixtures.report(amounts: [0, 1, 1], probability: 30)
        #expect(IslandRain.reading(from: report, now: now) == nil)
    }

    @Test func snowIsNotRain() {
        let report = RainFixtures.report(amounts: [0, 1, 1], condition: .snow)
        #expect(IslandRain.reading(from: report, now: now) == nil)
    }

    @Test func withoutAmountsTheWeatherCodeDecides() throws {
        let report = RainFixtures.codeOnly([.cloudy, .cloudy, .showers, .rain, .cloudy])
        let rain = try #require(IslandRain.reading(from: report, now: now))
        #expect(rain.phase == .starts(now.addingTimeInterval(7200)))
        #expect(rain.peakAmount == nil)
        #expect(rain.intensity == nil)
    }

    @Test func hoursInThePastAreIgnoredAndNoReportGivesNothing() {
        let report = RainFixtures.report(amounts: [1, 1], at: now.addingTimeInterval(-10 * 3600))
        #expect(IslandRain.reading(from: report, now: now) == nil)
        #expect(IslandRain.reading(from: nil, now: now) == nil)
    }

    @Test func theSpellKeepsItsKeyWhileTheForecastRefreshes() {
        let early = RainFixtures.report(amounts: [0, 0, 1, 1])
        let later = RainFixtures.report(amounts: [0, 0, 2, 0])
        let first = IslandRain.reading(from: early, now: now.addingTimeInterval(100))
        let second = IslandRain.reading(from: later, now: now.addingTimeInterval(1800))
        #expect(first?.key == second?.key)
    }
}

struct IslandRainEventTests {
    private let now = RainFixtures.now

    /// A snapshot taken at `date` from a forecast whose first hour starts at `base`.
    private func input(_ amounts: [Double?], base: Date? = nil, at date: Date) -> IslandInput {
        var input = IslandInput()
        input.rain = IslandRain.reading(from: RainFixtures.report(amounts: amounts, at: base ?? date), now: date)
        return input
    }

    @Test func announcesOnceAndOnlyWhenTheReadingChanges() throws {
        let dry = input([0, 0, 0, 0], at: now)
        let wet = input([0, 1, 1, 0], at: now)
        let events = IslandEventBuilder.events(current: wet, previous: dry, now: now)
        let rain = try #require(events.first { $0.kind == .weather })
        #expect(rain.id == "rain")
        #expect(try rain.detail == .weather(#require(wet.rain)))
        #expect(rain.expires == now.addingTimeInterval(IslandEventBuilder.transientDuration))
        // The same spell on the next refresh stays quiet.
        let refreshed = input([0, 2, 1, 0], base: now, at: now.addingTimeInterval(60))
        let quiet = IslandEventBuilder.events(current: refreshed, previous: wet, now: now.addingTimeInterval(60))
        #expect(quiet.allSatisfy { $0.kind != .weather })
    }

    @Test func theFirstSnapshotAndNoRainShowNothing() {
        let wet = input([0, 1, 1, 0], at: now)
        #expect(IslandEventBuilder.events(current: wet, previous: nil, now: now).isEmpty)
        #expect(IslandEventBuilder.events(current: IslandInput(), previous: wet, now: now).isEmpty)
    }

    @Test func rainThatBeginsIsAnnouncedAgainAsRainUnderway() throws {
        let soon = input([0, 1, 1, 0], at: now)
        let later = now.addingTimeInterval(3600 + 60)
        let raining = input([0, 1, 1, 0], base: now, at: later)
        let events = IslandEventBuilder.events(current: raining, previous: soon, now: later)
        let rain = try #require(events.first { $0.kind == .weather })
        #expect(try rain.detail == .weather(#require(raining.rain)))
    }

    @Test func rainEnteringTheWindowLaterIsAnnounced() {
        let far = input([0, 0, 0, 0, 1, 1], at: now)
        let near = input([0, 0, 0, 0, 1, 1], base: now, at: now.addingTimeInterval(3600))
        let events = IslandEventBuilder.events(current: near, previous: far, now: now.addingTimeInterval(3600))
        #expect(events.contains { $0.kind == .weather })
    }

    @Test func aNewSpellIsAnnouncedAgain() {
        let first = input([0, 1, 0, 0], at: now)
        let second = input([0, 0, 1, 0], at: now)
        let events = IslandEventBuilder.events(current: second, previous: first, now: now)
        #expect(events.contains { $0.kind == .weather })
    }
}
