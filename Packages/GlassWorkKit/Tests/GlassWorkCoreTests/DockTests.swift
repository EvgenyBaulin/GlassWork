import Foundation
@testable import GlassWorkCore
import Testing

struct DockLayoutTests {
    private let safari = DockApp(path: "/Applications/Safari.app", name: "Safari")
    private let mail = DockApp(path: "/Applications/Mail.app", name: "Mail")
    private let notes = DockApp(path: "/Applications/Notes.app", name: "Notes")

    private func folder(_ items: [DockItem]) -> AppFolder? {
        items.compactMap { item -> AppFolder? in
            if case let .folder(folder) = item {
                return folder
            }
            return nil
        }.first
    }

    @Test func droppingAnAppOnAnotherMakesAFolder() throws {
        let result = DockLayout.drop(mail, onto: safari, in: [.app(safari), .app(mail), .app(notes)])

        #expect(result.count == 2)
        let made = try #require(folder(result))
        #expect(made.apps == [safari, mail])
        #expect(result.last == .app(notes))
    }

    @Test func droppingAnAppOnItselfChangesNothing() {
        let items: [DockItem] = [.app(safari)]
        #expect(DockLayout.drop(safari, onto: safari, in: items) == items)
    }

    @Test func droppingIntoAFolderAddsOnce() throws {
        let base = AppFolder(name: "Work", apps: [safari, mail])
        let result = DockLayout.drop(notes, into: base, in: [.folder(base), .app(notes)])
        #expect(try #require(folder(result)).apps.count == 3)
        #expect(result.count == 1)
    }

    @Test func aFolderWithOneAppLeftDisappears() {
        let base = AppFolder(name: "Work", apps: [safari, mail])
        let result = DockLayout.remove(mail, from: base, in: [.folder(base)])
        #expect(result == [.app(mail), .app(safari)])
    }

    @Test func removingFromALargerFolderKeepsIt() throws {
        let base = AppFolder(name: "Work", apps: [safari, mail, notes])
        let result = DockLayout.remove(mail, from: base, in: [.folder(base)])
        #expect(try #require(folder(result)).apps == [safari, notes])
        #expect(result.last == .app(mail))
    }

    @Test func ungroupingPutsAppsBackInPlace() {
        let base = AppFolder(name: "Work", apps: [safari, mail])
        let items: [DockItem] = [.app(notes), .folder(base)]
        #expect(DockLayout.ungroup(base, in: items) == [.app(notes), .app(safari), .app(mail)])
    }

    @Test func sortingByNameOrdersApps() {
        var base = AppFolder(name: "Work", apps: [safari, mail])
        base.sort = .name
        #expect(base.sortedApps == [mail, safari])
    }
}

struct DockMagnificationTests {
    @Test func growsNearThePointer() {
        #expect(DockMagnification.size(distance: 0, base: 48, magnified: 80) == 80)
        #expect(DockMagnification.size(distance: 200, base: 48, magnified: 80) == 48)
        let halfway = DockMagnification.size(distance: 60, base: 48, magnified: 80)
        #expect(halfway > 48 && halfway < 80)
    }
}

struct SystemDockAppsTests {
    @Test func readsPinnedApps() {
        let apps = SystemDockApps.parse([
            ["tile-data": ["file-label": "Safari", "file-data": ["_CFURLString": "file:///Applications/Safari.app/"]]],
            ["tile-data": [:]],
        ])
        #expect(apps.count == 1)
        #expect(apps.first?.name == "Safari")
        #expect(apps.first?.path.hasPrefix("/Applications/Safari.app") == true)
    }
}
