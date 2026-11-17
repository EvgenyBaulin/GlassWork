import Foundation
@testable import GlassWorkCore
import Testing

/// Whether the Mac should be dark by the sun, for places and moments given in the test.
struct SunAppearanceTests {
    /// 2026-11-04 00:00 UTC. In London that day the sun rises about 06:50 and sets about 16:25 (UTC).
    private let midnight = Date(timeIntervalSince1970: 1_793_750_400)

    private func london(hour: Double) -> Bool? {
        SunAppearance.wantsDark(at: midnight.addingTimeInterval(hour * 3600), latitude: 51.48, longitude: 0)
    }

    @Test func itIsLightBetweenSunriseAndSunset() {
        #expect(london(hour: 8) == false)
        #expect(london(hour: 12) == false)
        #expect(london(hour: 16) == false)
    }

    @Test func itIsDarkAfterSunsetAndBeforeSunrise() {
        #expect(london(hour: 17) == true)
        #expect(london(hour: 23) == true)
        #expect(london(hour: 3) == true)
        #expect(london(hour: 6) == true)
    }

    @Test func theOtherSideOfTheWorldFollowsItsOwnSun() {
        func sydney(hour: Double) -> Bool? {
            SunAppearance.wantsDark(at: midnight.addingTimeInterval(hour * 3600), latitude: -33.87, longitude: 151.21)
        }
        // Noon in Sydney is 01:00 UTC, and midnight there is 13:00 UTC.
        #expect(sydney(hour: 1) == false)
        #expect(sydney(hour: 13) == true)
    }

    @Test func aPolarNightHasNothingToFollow() {
        #expect(SunAppearance.wantsDark(at: midnight, latitude: 80, longitude: 15) == nil)
    }

    private func look(hour: Double, next: Double?) -> SunAppearance.Look {
        SunAppearance.look(
            at: midnight.addingTimeInterval(hour * 3600),
            latitude: 51.48,
            longitude: 0,
            nextEvent: next.map { midnight.addingTimeInterval($0 * 3600) }
        )
    }

    @Test func theFirstLookAppliesTheCurrentSide() {
        let day = look(hour: 12, next: nil)
        #expect(day.dark == false)
        let sunset = try? #require(day.nextEvent)
        #expect(sunset.map { $0.timeIntervalSince(midnight) / 3600 > 16 } == true)
        #expect(look(hour: 20, next: nil).dark == true)
    }

    @Test func aClickHoldsUntilTheNextEventPasses() {
        let first = look(hour: 12, next: nil)
        let next = first.nextEvent.map { $0.timeIntervalSince(midnight) / 3600 }
        #expect(look(hour: 14, next: next).dark == nil)
        #expect(look(hour: 14, next: next).nextEvent == first.nextEvent)
    }

    @Test func aSunriseSleptThroughIsAppliedOnWaking() {
        // Dark was picked at noon on the 4th; the sunset at about 16:25 came and went during sleep.
        let sunset = look(hour: 12, next: nil).nextEvent.map { $0.timeIntervalSince(midnight) / 3600 }
        // Woken at noon the next day: the side of the day is light again, though it was light at the last look too.
        let woke = look(hour: 36, next: sunset)
        #expect(woke.dark == false)
        #expect((woke.nextEvent ?? .distantPast) > midnight.addingTimeInterval(36 * 3600))
        // Woken in the evening instead: dark.
        #expect(look(hour: 22, next: sunset).dark == true)
    }

    @Test func noPlaceToFollowDoesNothing() {
        let polar = SunAppearance.look(at: midnight, latitude: 80, longitude: 15, nextEvent: nil)
        #expect(polar == SunAppearance.Look(dark: nil, nextEvent: nil))
    }
}
