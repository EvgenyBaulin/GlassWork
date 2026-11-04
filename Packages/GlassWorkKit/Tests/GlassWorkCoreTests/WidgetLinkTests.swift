import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetLinkTests {
    @Test(arguments: [ModuleID.cpu, .fans, .aiUsage])
    func aModuleSurvivesTheRoundTrip(module: ModuleID) throws {
        let url = try #require(WidgetLink.url(for: module))
        #expect(WidgetLink.module(from: url) == module)
    }

    @Test func theSettingsPaneSurvivesTheRoundTrip() throws {
        let url = try #require(WidgetLink.url(for: WidgetDestination.widgetSettings))
        #expect(WidgetLink.destination(from: url) == .widgetSettings)
        #expect(WidgetLink.module(from: url) == nil)
    }

    @Test(arguments: [
        "glasswork://module/nothing",
        "glasswork://other/cpu",
        "https://module/cpu",
        "glasswork://settings/fans",
        "glasswork://settings/widgets/request",
        "https://settings/widgets",
    ])
    func anythingElseIsIgnored(address: String) throws {
        #expect(try WidgetLink.destination(from: #require(URL(string: address))) == nil)
    }
}
