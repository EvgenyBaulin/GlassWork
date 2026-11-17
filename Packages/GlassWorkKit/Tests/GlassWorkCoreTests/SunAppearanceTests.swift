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

    @Test func itSwitchesOnlyWhenTheSunsSideOfTheDayChanges() {
        // First look after the option was turned on.
        #expect(SunAppearance.change(wanted: true, last: nil) == true)
        #expect(SunAppearance.change(wanted: false, last: nil) == false)
        // Nothing changed since the last look, so a click on the Appearance item is left alone.
        #expect(SunAppearance.change(wanted: true, last: true) == nil)
        #expect(SunAppearance.change(wanted: false, last: false) == nil)
        // Sunrise and sunset.
        #expect(SunAppearance.change(wanted: false, last: true) == false)
        #expect(SunAppearance.change(wanted: true, last: false) == true)
        // No place or a polar night: nothing to do.
        #expect(SunAppearance.change(wanted: nil, last: true) == nil)
    }
}
