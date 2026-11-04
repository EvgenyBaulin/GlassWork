@testable import GlassWorkUI
import Testing

@MainActor
struct MenuBarRedrawTests {
    private let percent = 0.0 ... 1.0

    @Test
    func aChangeSmallerThanAPixelDrawsTheSameGraph() {
        let before = MenuBarItemRenderer.graphLevels([0.581, 0.582, 0.581], domain: percent)
        let after = MenuBarItemRenderer.graphLevels([0.582, 0.581, 0.583], domain: percent)
        #expect(before == after)
    }

    @Test
    func aVisibleChangeDrawsANewGraph() {
        let before = MenuBarItemRenderer.graphLevels([0.2, 0.2, 0.2], domain: percent)
        let after = MenuBarItemRenderer.graphLevels([0.2, 0.2, 0.3], domain: percent)
        #expect(before != after)
    }

    @Test
    func aLineMovingAlongTheGraphIsANewGraph() {
        let before = MenuBarItemRenderer.graphLevels([0.1, 0.5, 0.9], domain: percent)
        let after = MenuBarItemRenderer.graphLevels([0.5, 0.9, 0.1], domain: percent)
        #expect(before != after)
    }

    @Test
    func valuesOutsideTheDomainStopAtTheEdges() {
        #expect(MenuBarItemRenderer.graphLevels([-1, 2], domain: percent) == [0, 32])
    }

    @Test
    func withoutADomainTheHighestValueFillsTheGraph() {
        #expect(MenuBarItemRenderer.graphLevels([5, 10], domain: nil) == [16, 32])
    }
}
