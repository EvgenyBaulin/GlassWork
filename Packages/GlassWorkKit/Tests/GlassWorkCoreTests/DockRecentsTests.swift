import Foundation
@testable import GlassWorkCore
import Testing

struct DockRecentsTests {
    private let safari = DockApp(path: "/Applications/Safari.app", name: "Safari")
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let notes = DockApp(path: "/Applications/Notes.app", name: "Notes")
    private let maps = DockApp(path: "/Applications/Maps.app", name: "Maps")
    private let music = DockApp(path: "/Applications/Music.app", name: "Music")

    @Test func anAppUsedAgainMovesToTheFront() {
        let history = DockRecents.record(mail, in: [safari, mail, notes])

        #expect(history == [mail, safari, notes])
    }

    @Test func historyIsCapped() {
        let apps = (0 ..< 20).map { DockApp(path: "/Applications/A\($0).app", name: "A\($0)") }
        let history = apps.reduce([]) { DockRecents.record($1, in: $0) }

        #expect(history.count == DockRecents.remembered)
        #expect(history.first == apps.last)
    }

    @Test func pinnedAppsAreLeftOutAndOnlyThreeShow() {
        let shown = DockRecents.visible([safari, mail, notes, maps, music], pinned: [mail])

        #expect(shown == [safari, notes, maps])
    }

    @Test func recentsShowAfterADividerAndBeforeTheTrash() {
        let arrangement = DockArrangement(
            items: [.app(safari)],
            iconSize: 48,
            length: .infinity,
            showsTrash: true,
            recents: [mail, notes]
        )

        #expect(arrangement.slots == [.item(.app(safari)), .recent(mail), .recent(notes), .trash])
        #expect(arrangement.dividers == [0, 2])
    }

    @Test func recentsLeaveTheBarAsItWasWhenThereAreNone() {
        let arrangement = DockArrangement(items: [.app(safari)], iconSize: 48, length: .infinity, showsTrash: true)

        #expect(arrangement.slots == [.item(.app(safari)), .trash])
    }

    @MainActor
    @Test func liveStateShowsRecentsOnlyWhenSwitchedOn() {
        var settings = DockSettings()
        settings.items = [.app(safari)]
        let state = DockLiveState(settings: settings)
        state.recentApps = [mail]
        #expect(!state.arrangement.slots.contains(.recent(mail)))

        settings.showsRecents = true
        state.settings = settings
        #expect(state.arrangement.slots.contains(.recent(mail)))
    }
}

struct DockFolderSortTests {
    private let safari = DockApp(path: "/Applications/Safari.app", name: "Safari")
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let notes = DockApp(path: "/Applications/Notes.app", name: "Notes")

    @Test func mostUsedPutsTheBusiestFirstAndKeepsTiesInOrder() {
        var folder = AppFolder(name: "Work", apps: [safari, mail, notes])
        folder.sort = .mostUsed
        folder.launchCounts = [notes.path: 5, mail.path: 2, safari.path: 2]

        #expect(folder.sortedApps == [notes, safari, mail])
    }

    @Test func mostUsedWithoutCountsFallsBackToTheStoredOrder() {
        var folder = AppFolder(name: "Work", apps: [safari, mail, notes])
        folder.sort = .mostUsed

        #expect(folder.sortedApps == [safari, mail, notes])
    }

    @Test func nameSortingStillWorks() {
        var folder = AppFolder(name: "Work", apps: [safari, mail, notes])
        folder.sort = .name

        #expect(folder.sortedApps == [mail, notes, safari])
    }

    @Test func recordingALaunchCountsOnlyThatFolder() {
        let work = AppFolder(name: "Work", apps: [safari, mail])
        let other = AppFolder(name: "Other", apps: [safari, notes])
        let items = DockLayout.recordLaunch(safari, inFolder: work.id, in: [.folder(work), .folder(other)])

        guard case let .folder(first) = items[0], case let .folder(second) = items[1] else {
            Issue.record("folders expected")
            return
        }
        #expect(first.launchCounts == [safari.path: 1])
        #expect(second.launchCounts.isEmpty)
    }

    @Test func sortingAndRenamingFindTheFolderById() {
        let work = AppFolder(name: "Work", apps: [safari, mail])
        let sorted = DockLayout.sort(folder: work.id, by: .mostUsed, in: [.folder(work)])
        let renamed = DockLayout.rename(folder: work.id, to: "Play", in: sorted)

        guard case let .folder(result) = renamed[0] else {
            Issue.record("folder expected")
            return
        }
        #expect(result.sort == .mostUsed)
        #expect(result.name == "Play")
    }

    @Test func aFolderWrittenBeforeLaunchCountsStillLoads() throws {
        let json = #"{"name":"Work","apps":[{"path":"/Applications/Safari.app","name":"Safari"}],"sort":"mostUsed"}"#
        let folder = try JSONDecoder().decode(AppFolder.self, from: Data(json.utf8))

        #expect(folder.launchCounts.isEmpty)
        #expect(folder.sort == .mostUsed)
    }

    @Test func settingsWrittenBeforeTheIndicatorToggleKeepTheDotOn() throws {
        let settings = try JSONDecoder().decode(DockSettings.self, from: Data(#"{"isEnabled":true}"#.utf8))

        #expect(settings.showsRunningIndicators)
        #expect(settings.showsTrash)
    }

    @Test func theIndicatorChoiceSurvivesARoundTrip() throws {
        var settings = DockSettings()
        settings.showsRunningIndicators = false
        let data = try JSONEncoder().encode(settings)

        #expect(try !JSONDecoder().decode(DockSettings.self, from: data).showsRunningIndicators)
    }
}
