import Foundation
@testable import GlassWorkCore
import Testing

struct DockArrangementTests {
    private let apps = (0 ..< 8).map { DockItem.app(DockApp(path: "/Applications/\($0).app", name: "\($0)")) }
    private let widgets = ModuleID.dockWidgets.prefix(18).map(DockItem.widget)
    private let downloads = DockItem.stack(DockStack(path: "/tmp/stack", name: "Stack"))

    /// Room for exactly this many 48 pt slots.
    private func room(_ slots: Int) -> Double {
        DockBarLayout.restWidth(count: slots, base: 48)
    }

    private func items(in arrangement: DockArrangement) -> [DockItem] {
        arrangement.slots.compactMap { slot in
            if case let .item(item) = slot {
                return item
            }
            return nil
        }
    }

    @Test func everythingFitsAndNothingPages() {
        let all = apps + widgets.prefix(3)
        let arrangement = DockArrangement(items: all, iconSize: 48, length: 1512)
        #expect(arrangement.slots == all.map(DockSlot.item))
        #expect(arrangement.pageCount == 1)
        #expect(arrangement.hiddenWidgets == 0)
        #expect(arrangement.iconSize == 48)
    }

    @Test func anUnmeasuredScreenHasRoomForAll() {
        let arrangement = DockArrangement(items: apps + widgets, iconSize: 48, length: .infinity)
        #expect(arrangement.pageCount == 1)
        #expect(arrangement.slots.count == apps.count + widgets.count)
    }

    @Test func groupsAppsThenWidgetsThenStacks() {
        let mixed = [widgets[0], downloads, apps[0]]
        let arrangement = DockArrangement(items: mixed, iconSize: 48, length: 1512)
        #expect(items(in: arrangement) == [apps[0], widgets[0], downloads])
    }

    @Test func dividersStandBetweenGroups() {
        let arrangement = DockArrangement(items: [apps[0], apps[1], widgets[0], downloads], iconSize: 48, length: 1512)
        #expect(arrangement.dividers == [1, 2])
    }

    @Test func aSingleGroupHasNoDivider() {
        #expect(DockArrangement(items: apps, iconSize: 48, length: 1512).dividers.isEmpty)
        #expect(DockArrangement(items: Array(widgets.prefix(2)), iconSize: 48, length: 1512).dividers.isEmpty)
    }

    /// 8 apps, room for 16 slots, 2 of them buttons: 6 widgets a set, as in the design.
    @Test func widgetsThatDoNotFitArePaged() {
        let first = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16))
        #expect(first.pageCount == 3)
        #expect(first.page == 0)
        #expect(first.hiddenWidgets == 12)
        #expect(!first.slots.contains(.previousPage))
        #expect(first.slots.contains(.nextPage))
        #expect(items(in: first).count == 14)
    }

    @Test func aMiddleSetHasBothButtons() {
        let second = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16), page: 1)
        #expect(second.slots.contains(.previousPage))
        #expect(second.slots.contains(.nextPage))
    }

    @Test func everyWidgetIsOnExactlyOnePage() {
        var seen: [DockItem] = []
        for page in 0 ..< 3 {
            let arrangement = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16), page: page)
            seen += items(in: arrangement).filter { !apps.contains($0) }
        }
        #expect(seen == widgets)
    }

    @Test func noSetIsWiderThanTheScreen() {
        for page in 0 ..< 3 {
            let arrangement = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16), page: page)
            #expect(DockBarLayout.restWidth(count: arrangement.slots.count, base: 48) <= room(16))
        }
    }

    @Test func appsAndStacksStayOnEveryPage() {
        let all = apps + widgets + [downloads]
        for page in 0 ..< 3 {
            let shown = items(in: DockArrangement(items: all, iconSize: 48, length: room(17), page: page))
            #expect(shown.prefix(apps.count).elementsEqual(apps))
            #expect(shown.last == downloads)
        }
    }

    @Test func aPageThatNoLongerExistsFallsBackToTheLast() {
        let arrangement = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16), page: 40)
        #expect(arrangement.page == 2)
        let below = DockArrangement(items: apps + widgets, iconSize: 48, length: room(16), page: -3)
        #expect(below.page == 0)
    }

    @Test func iconsShrinkWhenAppsAloneDoNotFit() {
        let many = (0 ..< 30).map { DockItem.app(DockApp(path: "/\($0).app", name: "\($0)")) }
        let arrangement = DockArrangement(items: many, iconSize: 48, length: 900)
        #expect(arrangement.iconSize < 48)
        #expect(arrangement.slots.count == 30)
        #expect(DockBarLayout.restWidth(count: 30, base: arrangement.iconSize) <= 900)
    }

    @Test func iconsNeverShrinkPastLegible() {
        let many = (0 ..< 400).map { DockItem.app(DockApp(path: "/\($0).app", name: "\($0)")) }
        #expect(DockArrangement(items: many, iconSize: 48, length: 900).iconSize == DockArrangement.smallestIcon)
    }

    @Test func iconsNeverGrowToFill() {
        #expect(DockArrangement(items: apps, iconSize: 48, length: 5000).iconSize == 48)
    }

    @Test func anEmptyDockArrangesToNothing() {
        let arrangement = DockArrangement(items: [], iconSize: 48, length: 10)
        #expect(arrangement.slots.isEmpty)
        #expect(arrangement.pageCount == 1)
    }

    /// The bar and the window must agree, or the last tile would be cut off.
    @MainActor
    @Test func theWindowFollowsTheShrunkIcons() {
        var settings = DockSettings()
        settings.items = (0 ..< 30).map { DockItem.app(DockApp(path: "/\($0).app", name: "\($0)")) }
        let state = DockLiveState(settings: settings)
        state.available = 900
        let window = DockBarLayout.windowSize(
            for: .rest,
            count: state.arrangement.slots.count,
            settings: state.fittedSettings
        )
        #expect(window.width <= 900)
    }
}

struct DockCardOffsetTests {
    @Test func aSlotsMiddleMatchesTheBar() {
        #expect(DockBarLayout.slotCenter(0, count: 1, base: 48) == 0)
        #expect(DockBarLayout.slotCenter(1, count: 3, base: 48) == 0)
        #expect(DockBarLayout.slotCenter(2, count: 3, base: 48) == 56)
    }

    @Test func standsByItsTileWhileItFits() {
        #expect(DockBarLayout.cardOffset(center: 100, cardLength: 430, windowLength: 1000) == 100)
    }

    @Test func stopsAtTheWindowsEnds() {
        #expect(DockBarLayout.cardOffset(center: 500, cardLength: 430, windowLength: 1000) == 285)
        #expect(DockBarLayout.cardOffset(center: -500, cardLength: 430, windowLength: 1000) == -285)
    }

    @Test func aCardAsWideAsTheWindowStaysInTheMiddle() {
        #expect(DockBarLayout.cardOffset(center: 80, cardLength: 430, windowLength: 430) == 0)
    }
}

struct DockFilesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ name: String, age: Double = 0) -> DockFile {
        DockFile(path: "/stack/\(name)", name: name, added: now.addingTimeInterval(-age))
    }

    @Test func newestComesFirst() {
        let sorted = DockFiles.sorted([file("old", age: 90), file("new", age: 1), file("mid", age: 30)])
        #expect(sorted.map(\.name) == ["new", "mid", "old"])
    }

    @Test func theNameSettlesATie() {
        #expect(DockFiles.sorted([file("b"), file("a")]).map(\.name) == ["a", "b"])
    }

    @Test func searchIgnoresCaseAndSpaces() {
        let files = [file("Invoice.pdf"), file("photo.png")]
        #expect(DockFiles.matching(files, query: " INVO ").map(\.name) == ["Invoice.pdf"])
        #expect(DockFiles.matching(files, query: "").count == 2)
        #expect(DockFiles.matching(files, query: "zzz").isEmpty)
    }

    @Test(arguments: ["a.dmg.download", "a.dmg.crdownload", "a.dmg.part", "A.ZIP.CRDOWNLOAD"])
    func knowsAFileBeingDownloaded(name: String) {
        #expect(DockFiles.isPartial(name: name))
    }

    @Test func aFinishedFileIsNotPartial() {
        #expect(!DockFiles.isPartial(name: "a.dmg"))
        #expect(!DockFiles.isPartial(name: "download"))
    }

    @Test func aDownloadIsNamedAfterWhatItWillBecome() {
        #expect(DockFiles.displayName(of: "report.pdf.crdownload") == "report.pdf")
        #expect(DockFiles.displayName(of: "report.pdf") == "report.pdf")
    }

    @Test func readsProgressFromTheAttribute() {
        #expect(DockFiles.progress(fromAttribute: Data("0.62".utf8)) == 0.62)
        #expect(DockFiles.progress(fromAttribute: Data("1\0".utf8)) == 1)
    }

    @Test func aBadAttributeMeansUnknownProgress() {
        #expect(DockFiles.progress(fromAttribute: nil) == nil)
        #expect(DockFiles.progress(fromAttribute: Data("soon".utf8)) == nil)
        #expect(DockFiles.progress(fromAttribute: Data("7".utf8)) == nil)
        #expect(DockFiles.progress(fromAttribute: Data([0xFF, 0xFE])) == nil)
    }

    @Test func theTileAveragesWhatIsKnown() {
        var first = file("a")
        first.isDownloading = true
        first.progress = 0.2
        var second = file("b")
        second.isDownloading = true
        second.progress = 0.6
        var unknown = file("c")
        unknown.isDownloading = true
        let overall = DockFiles.overallProgress([first, second, unknown, file("done")])
        #expect(abs((overall ?? 0) - 0.4) < 0.0001)
    }

    @Test func nothingDownloadingShowsNoProgress() {
        #expect(DockFiles.overallProgress([file("a")]) == nil)
    }

    @Test func theFanCurvesLikeTheDesign() {
        #expect(DockFan.offset(at: 0) == 0)
        #expect(abs(DockFan.offset(at: 6) - 79.2) < 0.001)
    }
}

struct DockStackSettingsTests {
    private let stack = DockStack(path: "/tmp/docs", name: "Docs")

    @Test func aFanOnlyOpensAtTheBottom() {
        var fan = stack
        fan.style = .fan
        #expect(fan.showsFan(at: .bottom))
        #expect(!fan.showsFan(at: .left))
        #expect(!stack.showsFan(at: .bottom))
    }

    /// Reading a guarded folder can raise a macOS prompt, so nothing may be read until a stack is added.
    @Test func noStackMeansNoFolderIsRead() {
        var dock = DockSettings()
        dock.isEnabled = true
        #expect(dock.foldersToRead.isEmpty)
    }

    @Test func aDockThatIsOffReadsNoFolder() {
        var dock = DockSettings()
        dock.items = [.stack(stack)]
        #expect(dock.foldersToRead.isEmpty)
        dock.isEnabled = true
        #expect(dock.foldersToRead == ["/tmp/docs"])
    }

    @Test func aFolderIsAddedOnce() {
        var copy = stack
        copy.id = UUID()
        let items = DockLayout.adding(copy, to: DockLayout.adding(stack, to: []))
        #expect(items == [.stack(stack)])
    }

    @Test func downloadsIsMarkedAndNamed() {
        let downloads = DockStack.downloads(name: "Downloads")
        #expect(downloads.isDownloads)
        #expect(downloads.name == "Downloads")
        #expect(downloads.path.contains("Downloads"))
    }

    @Test func theStyleChangesOnlyOnThatStack() {
        let other = DockStack(path: "/tmp/other", name: "Other")
        let items = DockLayout.setting(.fan, of: stack, in: [.stack(stack), .stack(other)])
        var expected = stack
        expected.style = .fan
        #expect(items == [.stack(expected), .stack(other)])
    }

    @Test func aStackHoldsNoApps() {
        var dock = DockSettings()
        dock.items = [.stack(stack)]
        #expect(dock.apps.isEmpty)
    }

    @Test func survivesARoundTrip() throws {
        var dock = DockSettings()
        dock.items = [.stack(stack)]
        let copy = try JSONDecoder().decode(DockSettings.self, from: JSONEncoder().encode(dock))
        #expect(copy == dock)
    }

    @Test func aStackWithOnlyAPathStillLoads() throws {
        let loaded = try JSONDecoder().decode(DockStack.self, from: Data(#"{"path": "/tmp/a"}"#.utf8))
        #expect(loaded.path == "/tmp/a")
        #expect(loaded.style == .grid)
        #expect(!loaded.isDownloads)
    }
}

/// Runs on a folder made for the test, never on a real one.
struct DockFolderReaderTests {
    private func withFolder(_ body: (URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "dock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func write(_ name: String, in folder: URL, bytes: Int = 4) throws -> URL {
        let url = folder.appending(path: name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    @Test func readsSizesAndSkipsHiddenFiles() throws {
        try withFolder { folder in
            _ = try write("report.pdf", in: folder, bytes: 10)
            _ = try write(".DS_Store", in: folder)
            let files = DockFolderReader().read(folder.path(percentEncoded: false))
            #expect(files.map(\.name) == ["report.pdf"])
            #expect(files.first?.size == 10)
            #expect(files.first?.isDownloading == false)
        }
    }

    @Test func tellsFoldersFromFiles() throws {
        try withFolder { folder in
            try FileManager.default.createDirectory(
                at: folder.appending(path: "inner"),
                withIntermediateDirectories: true
            )
            #expect(DockFolderReader().read(folder.path(percentEncoded: false)).first?.isFolder == true)
        }
    }

    @Test func aPartialFileIsADownloadWithItsRealName() throws {
        try withFolder { folder in
            let url = try write("disk.dmg.crdownload", in: folder)
            let value = Data("0.25".utf8)
            let status = url.withUnsafeFileSystemRepresentation { path in
                value.withUnsafeBytes { setxattr(
                    path,
                    "com.apple.progress.fractionCompleted",
                    $0.baseAddress,
                    value.count,
                    0,
                    0
                ) }
            }
            #expect(status == 0)
            let file = try #require(DockFolderReader().read(folder.path(percentEncoded: false)).first)
            #expect(file.name == "disk.dmg")
            #expect(file.isDownloading)
            #expect(file.progress == 0.25)
        }
    }

    @Test func aMissingFolderReadsAsEmpty() {
        #expect(DockFolderReader().read("/no/such/folder/\(UUID().uuidString)").isEmpty)
    }
}
