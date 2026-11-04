import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetLinkTests {
    @Test(arguments: [ModuleID.cpu, .fans, .aiUsage])
    func aModuleSurvivesTheRoundTrip(module: ModuleID) throws {
        let url = try #require(WidgetLink.url(for: module))
        #expect(WidgetLink.module(from: url) == module)
    }

    @Test(arguments: ["glasswork://module/nothing", "glasswork://other/cpu", "https://module/cpu"])
    func anythingElseIsIgnored(address: String) throws {
        #expect(try WidgetLink.module(from: #require(URL(string: address))) == nil)
    }
}
