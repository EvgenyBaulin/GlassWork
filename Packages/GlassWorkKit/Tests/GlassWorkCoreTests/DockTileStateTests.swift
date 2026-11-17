@testable import GlassWorkCore
import Testing

struct DockTileStateTests {
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let slack = DockApp(path: "/Applications/Slack.app", name: "Slack")
    private let notes = DockApp(path: "/Applications/Notes.app", name: "Notes")

    @Test func badgeLabelsAreReadFromTheSystemDocksItems() {
        let items = [
            DockBadges.Item(url: "file:///Applications/Mail.app/", label: "3"),
            DockBadges.Item(url: "file:///Applications/My%20App.app/", label: "7"),
            DockBadges.Item(url: "file:///Applications/Notes.app/", label: nil),
            DockBadges.Item(url: "file:///Applications/Slack.app/", label: "0"),
            DockBadges.Item(url: "https://example.com", label: "5"),
            DockBadges.Item(url: nil, label: "9"),
        ]
        #expect(DockBadges.labels(from: items) == ["/Applications/Mail.app": "3", "/Applications/My App.app": "7"])
    }

    @Test func aNumberPastTheCapReadsAsPlus() {
        #expect(DockBadges.display("12") == "12")
        #expect(DockBadges.display("100") == "99+")
        #expect(DockBadges.display("1500") == "99+")
        #expect(DockBadges.display("0") == nil)
        #expect(DockBadges.display(nil) == nil)
    }

    @Test func aWordBadgeStaysAsItIs() {
        #expect(DockBadges.display("•") == "•")
        #expect(DockBadges.display("New") == "New")
    }

    @Test func aFolderAddsItsAppsBadges() {
        #expect(DockBadges.total(of: ["3", "4"]) == "7")
        #expect(DockBadges.total(of: ["60", "50"]) == "99+")
        #expect(DockBadges.total(of: ["2", "99+"]) == "99+")
    }

    @Test func wordsCountForNothingNextToNumbersAndForADotAlone() {
        #expect(DockBadges.total(of: ["2", "•"]) == "2")
        #expect(DockBadges.total(of: ["•", "New"]) == "•")
        #expect(DockBadges.total(of: []) == nil)
        #expect(DockBadges.total(of: ["0", ""]) == nil)
    }

    @Test func anAppTileTakesItsBadgeAndTheSetsItIsIn() {
        let state = DockTileStates.state(
            for: mail,
            badges: ["/Applications/Mail.app": "5"],
            attention: [mail.path],
            hidden: [mail.path]
        )
        #expect(state == DockTileState(badge: "5", needsAttention: true, isHidden: true))
        #expect(DockTileStates.state(for: notes, badges: [:], attention: [], hidden: []) == DockTileState())
    }

    @Test func aFolderSumsBadgesAsksIfAnyAppDoesAndNeverDims() {
        let folder = AppFolder(name: "Chat", apps: [mail, slack, notes])
        let badges = [mail.path: "2", slack.path: "3"]
        let state = DockTileStates.state(for: folder, badges: badges, attention: [slack.path])
        #expect(state == DockTileState(badge: "5", needsAttention: true, isHidden: false))
    }

    @Test func aBadgeThatGrowsOnAnAppNotInFrontAsksForAttention() {
        var attention = DockAttention()
        attention.update(labels: [mail.path: "2"], front: nil)
        #expect(attention.asking.isEmpty)
        attention.update(labels: [mail.path: "3"], front: nil)
        #expect(attention.asking == [mail.path])
        // Still waiting, unchanged: it keeps asking.
        attention.update(labels: [mail.path: "3"], front: nil)
        #expect(attention.asking == [mail.path])
    }

    @Test func comingToTheFrontOrClearingTheBadgeEndsTheRequest() {
        var attention = DockAttention()
        attention.update(labels: [:], front: nil)
        attention.update(labels: [mail.path: "1", slack.path: "1"], front: nil)
        #expect(attention.asking == [mail.path, slack.path])
        attention.update(labels: [mail.path: "1"], front: mail.path)
        #expect(attention.asking.isEmpty)
    }

    @Test func aFallingBadgeIsNoRequest() {
        var attention = DockAttention()
        attention.update(labels: [mail.path: "5"], front: nil)
        attention.update(labels: [mail.path: "4"], front: nil)
        #expect(attention.asking.isEmpty)
    }
}
