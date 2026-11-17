@testable import GlassWorkCore
import Testing

struct DockRecoveryTests {
    @Test func savedSettingsAtLaunchMeanTheLastRunDidNotGiveTheDockBack() {
        #expect(DockRecovery.decide(markerExists: true, hasSavedSettings: true) == .restore)
    }

    /// A run from before the marker existed that crashed.
    @Test func savedSettingsWithoutAMarkerAreRestoredToo() {
        #expect(DockRecovery.decide(markerExists: false, hasSavedSettings: true) == .restore)
    }

    /// Nothing to put back, so no restore and no toast: only the stale marker goes.
    @Test func aMarkerWithNothingSavedIsOnlyCleared() {
        #expect(DockRecovery.decide(markerExists: true, hasSavedSettings: false) == .clearMarker)
    }

    @Test func aCleanLaunchDoesNothing() {
        #expect(DockRecovery.decide(markerExists: false, hasSavedSettings: false) == .nothing)
    }
}
