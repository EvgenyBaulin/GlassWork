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

struct DockPositionTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let size = CGSize(width: 71, height: 288)

    private func settings(_ position: DockPosition) -> DockSettings {
        var settings = DockSettings()
        settings.iconSize = 48
        settings.magnifies = true
        settings.magnifiedSize = 80
        settings.position = position
        return settings
    }

    @Test func aSideDockSwapsTheWindowsAxes() {
        let bottom = DockBarLayout.windowSize(for: .rest, count: 5, settings: settings(.bottom))
        let left = DockBarLayout.windowSize(for: .rest, count: 5, settings: settings(.left))
        #expect(left.width == bottom.height)
        #expect(left.height == bottom.width)
    }

    @Test(arguments: [DockPosition.left, .right])
    func aSideDocksCardStandsBesideTheBar(position: DockPosition) {
        let rest = DockBarLayout.windowSize(for: .rest, count: 2, settings: settings(position))
        let card = DockBarLayout.windowSize(for: .folder, count: 2, settings: settings(position))
        #expect(card.width >= rest.width + DockBarLayout.folderCardWidth)
        #expect(card.height >= DockBarLayout.folderCardHeight)
    }

    @Test(arguments: DockPosition.allCases)
    func everyWindowSizeSharesOneMiddleAlongTheBar(position: DockPosition) {
        for space in [DockSpace.rest, .magnified, .folder] {
            let window = DockBarLayout.windowSize(for: space, count: 7, settings: settings(position))
            let length = position.isVertical ? window.height : window.width
            #expect(length.truncatingRemainder(dividingBy: 2) == 0)
        }
    }

    @Test func standsOnTheBottomEdgeInTheMiddle() {
        let frame = DockBarLayout.windowFrame(
            size: CGSize(width: 288, height: 71), position: .bottom, screen: screen, topInset: 33
        )
        #expect(frame == CGRect(x: 612, y: 4, width: 288, height: 71))
    }

    @Test func aSideDockIsCenteredBelowTheMenuBar() {
        let left = DockBarLayout.windowFrame(size: size, position: .left, screen: screen, topInset: 32)
        let right = DockBarLayout.windowFrame(size: size, position: .right, screen: screen, topInset: 32)
        #expect(left == CGRect(x: 4, y: 331, width: 71, height: 288))
        #expect(right == CGRect(x: 1437, y: 331, width: 71, height: 288))
    }

    @Test func staysOnItsEdgeOnASecondaryOrigin() {
        let shifted = CGRect(x: -1000, y: 200, width: 1000, height: 800)
        let frame = DockBarLayout.windowFrame(size: size, position: .right, screen: shifted, topInset: 0)
        #expect(frame == CGRect(x: -75, y: 456, width: 71, height: 288))
    }

    @Test(arguments: DockPosition.allCases)
    func aHiddenDockIsEntirelyPastItsEdge(position: DockPosition) {
        let hidden = DockBarLayout.windowFrame(
            size: size, position: position, screen: screen, topInset: 32, isRevealed: false
        )
        #expect(!hidden.intersects(screen))
        let shown = DockBarLayout.windowFrame(size: size, position: position, screen: screen, topInset: 32)
        // It slides straight out: along the bar nothing changes.
        if position.isVertical {
            #expect(hidden.minY == shown.minY)
        } else {
            #expect(hidden.minX == shown.minX)
        }
    }

    @Test func aDockThatHidesItselfLeavesTheScreenToWindows() {
        var dock = settings(.bottom)
        dock.isEnabled = true
        #expect(DockBarLayout.reservedDepth(dock) == DockBarLayout.screenGap + DockBarLayout.restHeight(base: 48))
        dock.autoHides = true
        #expect(DockBarLayout.reservedDepth(dock) == 0)
        dock.autoHides = false
        dock.isEnabled = false
        #expect(DockBarLayout.reservedDepth(dock) == 0)
    }

    @Test func windowsKeepClearOfTheEdgeTheDockIsOn() {
        let visible = CGRect(x: 0, y: 4, width: 1512, height: 946)
        let display = TileDisplay(frame: screen, visibleFrame: visible)
        #expect(display.reserving(75, at: .left).visibleFrame == CGRect(x: 75, y: 4, width: 1437, height: 946))
        #expect(display.reserving(75, at: .right).visibleFrame == CGRect(x: 0, y: 4, width: 1437, height: 946))
        #expect(display.reserving(75, at: .bottom).visibleFrame.minY == 75)
        #expect(display.reserving(0, at: .left).visibleFrame == visible)
    }
}

struct DockAutoHideTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let bar = CGRect(x: 600, y: 4, width: 300, height: 71)
    private let side = CGRect(x: 4, y: 300, width: 71, height: 300)

    @Test func thePointerRevealsTheDockOnlyAlongTheBar() {
        func touches(_ x: Double, _ y: Double) -> Bool {
            DockAutoHide.touchesEdge(CGPoint(x: x, y: y), barFrame: bar, position: .bottom, screen: screen)
        }
        #expect(touches(700, 0))
        #expect(!touches(700, 3))
        #expect(!touches(100, 0))
    }

    @Test func aSideDockRevealsAtItsOwnEdge() {
        func touches(_ x: Double, _ position: DockPosition) -> Bool {
            DockAutoHide.touchesEdge(CGPoint(x: x, y: 400), barFrame: side, position: position, screen: screen)
        }
        #expect(touches(0, .left))
        #expect(!touches(1511, .left))
        #expect(touches(1511, .right))
        #expect(!touches(0, .right))
    }

    @Test func theGapUnderTheBarCountsAsTheDock() {
        #expect(DockAutoHide.isOver(CGPoint(x: 700, y: 1), frame: bar))
        #expect(!DockAutoHide.isOver(CGPoint(x: 700, y: 120), frame: bar))
    }

    private func revealed(
        autoHides: Bool = true,
        was: Bool = false,
        over: Bool = false,
        edge: Bool = false,
        held: Bool = false
    ) -> Bool {
        DockAutoHide.isRevealed(
            autoHides: autoHides, wasRevealed: was, isOverDock: over, touchesEdge: edge, isHeld: held
        )
    }

    @Test func aDockThatStaysIsAlwaysShown() {
        #expect(revealed(autoHides: false))
    }

    @Test func staysHiddenUntilThePointerTouchesTheEdge() {
        #expect(!revealed())
        #expect(revealed(edge: true))
    }

    /// The window sits there while hidden, so being over its frame must not count until it has been shown.
    @Test func overTheHiddenFrameDoesNotReveal() {
        #expect(!revealed(was: false, over: true))
    }

    @Test func staysWhileThePointerIsOnIt() {
        #expect(revealed(was: true, over: true))
        #expect(!revealed(was: true, over: false))
    }

    @Test func anOpenCardOrMenuHoldsItOpen() {
        #expect(revealed(was: true, held: true))
        #expect(revealed(was: false, held: true))
    }
}

struct DockSettingsFileTests {
    private func decode(_ json: String) throws -> DockSettings {
        try JSONDecoder().decode(DockSettings.self, from: Data(json.utf8))
    }

    /// Exactly what the version before this one wrote: a new setting must never make this fail, because a throw
    /// here loses the whole settings file.
    @Test func readsAFileFromBeforeANewSetting() throws {
        let dock = try decode("""
        {"isEnabled": true, "position": "left", "iconSize": 60, "magnifies": true, "magnifiedSize": 90,
         "autoHides": true, "showsRecents": false,
         "items": [{"app": {"_0": {"path": "/Applications/Mail.app", "name": "Mail"}}}]}
        """)
        #expect(dock.isEnabled)
        #expect(dock.position == .left)
        #expect(dock.iconSize == 60)
        #expect(dock.autoHides)
        #expect(dock.items == [.app(DockApp(path: "/Applications/Mail.app", name: "Mail"))])
    }

    @Test func missingKeysFallBackToDefaults() throws {
        #expect(try decode("{}") == DockSettings())
    }

    @Test func anItemItCannotReadDoesNotCostTheRest() throws {
        let dock = try decode("""
        {"items": [{"hologram": {"_0": 1}}, {"widget": {"_0": "cpu"}}, {"widget": {"_0": "noSuchModule"}}]}
        """)
        #expect(dock.items == [.widget(.cpu)])
    }

    @Test func aFolderFromBeforeANewFieldStillLoads() throws {
        let id = UUID()
        let folder = try JSONDecoder().decode(AppFolder.self, from: Data("""
        {"id": "\(id.uuidString)", "name": "Work", "apps": []}
        """.utf8))
        #expect(folder.id == id)
        #expect(folder.sort == .manual)
    }

    @Test func survivesARoundTrip() throws {
        var dock = DockSettings()
        dock.position = .right
        dock.items = [.widget(.battery), .folder(AppFolder(name: "Work", apps: []))]
        let copy = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(dock))
        #expect(copy == dock)
    }
}

struct DockLaunchTrackerTests {
    private let path = "/Applications/Mail.app"
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aClickStartsTheBounce() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: false, at: start)
        #expect(tracker.launching == [path])
        #expect(tracker.nextDeadline == start.addingTimeInterval(DockLaunchTracker.timeout))
    }

    @Test func aRunningAppDoesNotBounce() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: true, at: start)
        #expect(tracker.launching.isEmpty)
    }

    @Test func stopsOnceTheAppRuns() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: false, at: start)
        tracker.update(running: [path], at: start.addingTimeInterval(1))
        #expect(tracker.launching.isEmpty)
        #expect(tracker.nextDeadline == nil)
    }

    @Test func stopsOnAFailedLaunch() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: false, at: start)
        tracker.fail(path)
        #expect(tracker.launching.isEmpty)
    }

    @Test func stopsAtTheTimeout() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: false, at: start)
        tracker.update(running: [], at: start.addingTimeInterval(DockLaunchTracker.timeout - 1))
        #expect(tracker.launching == [path])
        tracker.update(running: [], at: start.addingTimeInterval(DockLaunchTracker.timeout))
        #expect(tracker.launching.isEmpty)
    }

    @Test func otherAppsKeepBouncing() {
        var tracker = DockLaunchTracker()
        tracker.begin(path, isRunning: false, at: start)
        tracker.begin("/Applications/Notes.app", isRunning: false, at: start)
        tracker.update(running: [path], at: start)
        #expect(tracker.launching == ["/Applications/Notes.app"])
    }
}

struct DockRunningAppsTests {
    private let safari = DockApp(path: "/Applications/Safari.app/", name: "Safari")
    private let mail = DockApp(path: "/System/Applications/Mail.app/", name: "Mail")

    @Test func matchesAcrossALinkByBundleID() {
        let running = [RunningApp(
            bundleID: "com.apple.Safari",
            path: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app/"
        )]
        let bundleIDs = [safari.path: "com.apple.Safari"]
        #expect(DockRunningApps.match([safari, mail], bundleIDs: bundleIDs, running: running) == [safari.path])
    }

    @Test func fallsBackToThePathWithoutItsSlash() {
        let running = [RunningApp(bundleID: nil, path: "/System/Applications/Mail.app")]
        #expect(DockRunningApps.match([mail], bundleIDs: [:], running: running) == [mail.path])
    }

    @Test func aQuitAppIsNoLongerMatched() {
        #expect(DockRunningApps.match([mail], bundleIDs: [mail.path: "com.apple.mail"], running: []).isEmpty)
    }

    @Test func seesAppsInFolders() {
        var settings = DockSettings()
        settings.items = [.app(safari), .folder(AppFolder(name: "Work", apps: [mail])), .widget(.cpu)]
        #expect(settings.apps == [safari, mail])
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
