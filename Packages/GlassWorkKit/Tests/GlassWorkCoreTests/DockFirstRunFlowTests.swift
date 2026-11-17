@testable import GlassWorkCore
import Testing

struct DockFirstRunFlowTests {
    @Test func withoutAccessibilityTheIntroLeadsToTheWaitingStep() {
        #expect(DockFirstRunStep.intro.next(isTrusted: false, hasPresets: true) == .accessibility)
        #expect(DockFirstRunStep.intro.next(isTrusted: false, hasPresets: false) == .accessibility)
    }

    @Test func withAccessibilityAlreadyGrantedTheWaitingStepIsSkipped() {
        #expect(DockFirstRunStep.intro.next(isTrusted: true, hasPresets: true) == .preset)
    }

    @Test func theWaitingStepLeadsToThePresetsOnceTheyAreOffered() {
        #expect(DockFirstRunStep.accessibility.next(isTrusted: true, hasPresets: true) == .preset)
        // Limited mode: still not granted, the way on is the same.
        #expect(DockFirstRunStep.accessibility.next(isTrusted: false, hasPresets: true) == .preset)
    }

    @Test func withNoPresetsOnOfferTheFlowEndsEarly() {
        #expect(DockFirstRunStep.intro.next(isTrusted: true, hasPresets: false) == nil)
        #expect(DockFirstRunStep.accessibility.next(isTrusted: false, hasPresets: false) == nil)
    }

    @Test func thePresetStepIsTheLast() {
        #expect(DockFirstRunStep.preset.next(isTrusted: false, hasPresets: true) == nil)
    }
}
