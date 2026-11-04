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

    @Test func fallsOffLikeTheDesign() {
        let step = 48.0 + DockBarLayout.spacing
        func scale(_ tiles: Double) -> Double {
            DockMagnification.size(distance: tiles * step, base: 48, magnified: 48 * 1.6) / 48
        }
        #expect(abs(scale(0) - 1.6) < 0.001)
        #expect(abs(scale(1) - 1.35) < 0.1)
        #expect(abs(scale(2) - 1.12) < 0.05)
        #expect(scale(3) == 1)
    }

    @Test func reachFollowsTheIconSize() {
        #expect(DockMagnification.size(distance: 200, base: 96, magnified: 128) > 96)
    }
}

struct DockBarLayoutTests {
    private let base = 48.0
    private let magnified = 108.0

    /// Every pointer position across the bar and a little past both ends.
    private func sweep(count: Int) -> [Double] {
        let half = DockBarLayout.restWidth(count: count, base: base) / 2 + 40
        return stride(from: -half, through: half, by: 1).map(\.self)
    }

    private func layout(_ count: Int, _ pointer: Double?) -> DockBarLayout {
        DockBarLayout(count: count, base: base, magnified: magnified, pointer: pointer)
    }

    @Test func restsCenteredAtBaseSize() {
        let rest = layout(5, nil)
        #expect(rest.sizes == Array(repeating: 48, count: 5))
        #expect(rest.width == 5 * 48 + 4 * 8 + 16)
        #expect(rest.centerX == 0)
    }

    @Test func anEmptyDockIsJustItsPadding() {
        let empty = layout(0, 10)
        #expect(empty.sizes.isEmpty)
        #expect(empty.width == 16)
    }

    @Test func keepsWidthAndSizesInStep() {
        for pointer in sweep(count: 9) {
            let bar = layout(9, pointer)
            #expect(abs(bar.width - bar.sizes.reduce(0, +) - 8 * 8 - 16) < 0.001)
        }
    }

    /// A small move of the pointer must never make anything jump.
    @Test func movesSmoothly() {
        let positions = sweep(count: 9)
        for (previous, next) in zip(positions, positions.dropFirst()) {
            let before = layout(9, previous)
            let after = layout(9, next)
            #expect(abs(before.minX - after.minX) < 3)
            #expect(abs(before.width - after.width) < 3)
            for (old, new) in zip(before.sizes, after.sizes) {
                #expect(abs(old - new) < 3)
            }
        }
    }

    @Test func thePointerStaysOnTheIconItEntered() {
        let count = 9
        let step = base + DockBarLayout.spacing
        let firstCenter = -DockBarLayout.restWidth(count: count, base: base) / 2 + DockBarLayout.padding + base / 2
        for index in 0 ..< count {
            let pointer = firstCenter + Double(index) * step
            let bar = layout(count, pointer)
            let left = bar.minX + DockBarLayout.padding
                + bar.sizes.prefix(index).reduce(0) { $0 + $1 + DockBarLayout.spacing }
            #expect(pointer >= left && pointer <= left + bar.sizes[index])
            #expect(abs(pointer - (left + bar.sizes[index] / 2)) < 0.001)
        }
    }

    @Test func neighboursMakeRoomOnBothSides() {
        let rest = layout(9, nil)
        let bar = layout(9, 0)
        #expect(bar.minX < rest.minX)
        #expect(bar.minX + bar.width > rest.minX + rest.width)
        #expect(abs(bar.centerX) < 0.001)
    }

    @Test(arguments: [1, 2, 5, 24])
    func theWindowHoldsTheBarWhereverThePointerIs(count: Int) {
        var settings = DockSettings()
        settings.iconSize = base
        settings.magnifiedSize = magnified
        settings.magnifies = true
        let window = DockBarLayout.windowSize(for: .magnified, count: count, settings: settings)
        for pointer in sweep(count: count) {
            let bar = layout(count, pointer)
            #expect(bar.minX >= -window.width / 2)
            #expect(bar.minX + bar.width <= window.width / 2)
            let top = bar.sizes.max().map { $0 + DockBarLayout.indicator + 2 * DockBarLayout.padding } ?? 0
            #expect(top <= window.height)
        }
    }

    @Test func aRestingWindowIsJustTheBar() {
        var settings = DockSettings()
        settings.iconSize = 48
        let window = DockBarLayout.windowSize(for: .rest, count: 5, settings: settings)
        #expect(window.width == 288)
        #expect(window.height == 71)
    }

    @Test func everyWindowSizeSharesOneMiddle() {
        var settings = DockSettings()
        settings.iconSize = 49.03
        settings.magnifiedSize = 108.6
        settings.magnifies = true
        for space in [DockSpace.rest, .magnified, .folder] {
            let window = DockBarLayout.windowSize(for: space, count: 7, settings: settings)
            #expect(window.width.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    @Test func aFolderCardFitsAboveASmallBar() {
        var settings = DockSettings()
        settings.iconSize = 48
        let window = DockBarLayout.windowSize(for: .folder, count: 2, settings: settings)
        #expect(window.width >= DockBarLayout.folderCardWidth)
        #expect(window.height >= DockBarLayout.folderCardHeight + DockBarLayout.restHeight(base: 48))
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
