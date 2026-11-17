@testable import GlassWorkCore
import Testing

struct MenuBarSearchTests {
    private func entry(
        _ app: String,
        title: String? = nil,
        pid: Int32 = 1,
        index: Int = 0,
        x: Double = 0
    ) -> MenuBarEntry {
        MenuBarEntry(pid: pid, index: index, appName: app, title: title, minX: x, width: 24)
    }

    @Test
    func labelPrefersTitleThenDescriptionThenHelp() {
        #expect(MenuBarEntry.label(title: "T", description: "D", help: "H") == "T")
        #expect(MenuBarEntry.label(title: "  ", description: "D", help: "H") == "D")
        #expect(MenuBarEntry.label(title: nil, description: "", help: " H ") == "H")
        #expect(MenuBarEntry.label(title: nil, description: nil, help: nil) == nil)
    }

    @Test
    func nameFallsBackToTheApp() {
        #expect(entry("Dropbox").name == "Dropbox")
        #expect(entry("Dropbox", title: "Sync").name == "Sync")
    }

    @Test
    func sectionsFollowTheSeparators() {
        let item = entry("A", x: 100)
        #expect(MenuBarSearch.section(of: item, separatorMaxX: 500, alwaysHiddenMaxX: nil) == .hidden)
        #expect(MenuBarSearch.section(of: item, separatorMaxX: 500, alwaysHiddenMaxX: 300) == .alwaysHidden)
        #expect(MenuBarSearch.section(of: item, separatorMaxX: 50, alwaysHiddenMaxX: 20) == .visible)
        #expect(MenuBarSearch.section(of: item, separatorMaxX: nil, alwaysHiddenMaxX: nil) == .visible)
    }

    @Test
    func collapsedItemsFarOffScreenCountAsHidden() {
        let item = entry("A", x: -9000)
        #expect(MenuBarSearch.section(of: item, separatorMaxX: 1200, alwaysHiddenMaxX: nil) == .hidden)
    }

    @Test
    func candidatesAreTheHiddenItemsClosestToTheClockFirst() {
        let entries = [entry("Far", x: 10), entry("Shown", x: 900), entry("Near", x: 300)]
        let hidden = MenuBarSearch.candidates(entries, separatorMaxX: 500, alwaysHiddenMaxX: nil, showAll: false)
        #expect(hidden.map(\.appName) == ["Near", "Far"])
        let all = MenuBarSearch.candidates(entries, separatorMaxX: 500, alwaysHiddenMaxX: nil, showAll: true)
        #expect(all.map(\.appName) == ["Shown", "Near", "Far"])
    }

    @Test
    func withoutASeparatorOnlyShowAllListsAnything() {
        let entries = [entry("A", x: 10)]
        #expect(MenuBarSearch.candidates(entries, separatorMaxX: nil, alwaysHiddenMaxX: nil, showAll: false).isEmpty)
        #expect(MenuBarSearch.candidates(entries, separatorMaxX: nil, alwaysHiddenMaxX: nil, showAll: true).count == 1)
    }

    @Test
    func emptyQueryKeepsTheOrder() {
        let entries = [entry("B"), entry("A")]
        #expect(MenuBarSearch.results(entries, query: "  ").map(\.appName) == ["B", "A"])
    }

    @Test
    func caseAndAccentsDoNotMatter() {
        let entries = [entry("Café Timer"), entry("Other")]
        #expect(MenuBarSearch.results(entries, query: "CAFE").map(\.appName) == ["Café Timer"])
        #expect(MenuBarSearch.results(entries, query: "café").map(\.appName) == ["Café Timer"])
    }

    @Test
    func rankingPrefersPrefixThenWordThenContainsThenApp() {
        let entries = [
            entry("Host", title: "Email", pid: 1),
            entry("Mail", title: "Inbox", pid: 2),
            entry("Host", title: "Quick mail", pid: 3),
            entry("Mailbox", pid: 4),
            entry("Host", title: "Unrelated", pid: 5),
        ]
        let found = MenuBarSearch.results(entries, query: "mail")
        #expect(found.map(\.pid) == [4, 3, 1, 2])
    }

    @Test
    func equalRanksKeepTheirOrder() {
        let entries = [entry("Bee", index: 0), entry("Beta", index: 1)]
        #expect(MenuBarSearch.results(entries, query: "be").map(\.index) == [0, 1])
    }

    @Test
    func noMatchIsEmpty() {
        #expect(MenuBarSearch.results([entry("A")], query: "zzz").isEmpty)
    }
}
