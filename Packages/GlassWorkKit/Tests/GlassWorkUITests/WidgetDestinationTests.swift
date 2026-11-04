import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import Testing

struct WidgetDestinationTests {
    @Test(arguments: WidgetKind.allCases)
    func everyWidgetLeadsSomewhere(kind: WidgetKind) throws {
        let url = try #require(WidgetLink.url(for: kind.destination))
        switch kind.destination {
        case let .web(page):
            #expect(page.scheme == "https")
            #expect(WidgetLink.destination(from: url) == nil)
        default:
            #expect(WidgetLink.destination(from: url) == kind.destination)
        }
    }

    /// Overview says nothing about a clock or a pull request, so only the widgets about the whole Mac may end there.
    @Test func overviewIsOnlyForTheMacAsAWhole() {
        let leads = WidgetKind.allCases.filter { $0.destination == .module(.overview) }
        #expect(Set(leads) == [.activity, .macHealth])
    }

    @Test func theWidgetsThatReadPersonalDataOpenTheirSwitches() {
        for kind in WidgetKind.personalKinds {
            #expect(kind.destination == .widgetSettings)
        }
    }

    @Test func everyWidgetHasATitle() {
        #expect(WidgetKind.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
