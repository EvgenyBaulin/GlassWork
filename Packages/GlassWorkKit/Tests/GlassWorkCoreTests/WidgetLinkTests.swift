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

    private var shown: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: Date())
        snapshot.github = WidgetGitHub(mine: [PullRequestSummary(
            title: "Feed",
            repository: "o/r",
            number: 145,
            url: "https://github.com/o/r/pull/145",
            updatedAt: Date()
        )])
        snapshot.events = [AgendaEvent(
            id: "1",
            title: "Call",
            start: Date(),
            end: Date(),
            callURL: URL(string: "https://example.com/call")
        )]
        return snapshot
    }

    @Test(arguments: ["https://github.com/o/r/pull/145", "https://example.com/call"])
    func anAddressOnTheWidgetIsAccepted(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(WidgetLink.destination(from: url, shownIn: shown) == .web(url))
    }

    @Test(arguments: [
        "https://evil.example/o/r/pull/145",
        "http://github.com/o/r/pull/145",
        "https://github.com/o/r/pull/146",
        "https://github.com/settings/tokens",
        "file:///etc/hosts",
    ])
    func anythingNotOnTheWidgetIsRefused(address: String) throws {
        #expect(try WidgetLink.destination(from: #require(URL(string: address)), shownIn: shown) == nil)
    }

    @Test func withoutASnapshotOnlyTheFixedPagesPass() throws {
        let home = try #require(WidgetLink.githubHome)
        let reviews = try #require(WidgetLink.githubReviews)
        #expect(WidgetLink.destination(from: home, shownIn: nil) == .web(home))
        #expect(WidgetLink.destination(from: reviews, shownIn: nil) == .web(reviews))
        let pull = try #require(URL(string: "https://github.com/o/r/pull/145"))
        #expect(WidgetLink.destination(from: pull, shownIn: nil) == nil)
    }

    @Test func ownAddressesNeedNoSnapshot() throws {
        let url = try #require(WidgetLink.url(for: ModuleID.cpu))
        #expect(WidgetLink.destination(from: url, shownIn: nil) == .module(.cpu))
    }
}
