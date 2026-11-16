import Foundation
@testable import GlassWorkCore
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

/// A shelf folder and a folder of "user" files, both removed when the test ends.
@MainActor
private struct Workspace {
    let shelfFolder = temporaryFolder()
    let userFolder = temporaryFolder()

    init() throws {
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
    }

    func file(_ name: String, bytes: Int = 10) throws -> URL {
        let url = userFolder.appending(path: name, directoryHint: .notDirectory)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func store(_ settings: ShelfSettings = ShelfSettings()) -> ShelfStore {
        let store = ShelfStore(folder: shelfFolder)
        store.apply(settings)
        return store
    }

    func finish() {
        try? FileManager.default.removeItem(at: shelfFolder)
        try? FileManager.default.removeItem(at: userFolder)
    }

    func copies() -> [String] {
        let files = shelfFolder.appending(path: "Files", directoryHint: .isDirectory)
        return (try? FileManager.default.contentsOfDirectory(atPath: files.path(percentEncoded: false))) ?? []
    }
}

@MainActor
struct ShelfTests {
    @Test func keepsAReferenceByDefault() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let url = try space.file("invoice.pdf", bytes: 42)
        await store.add([url], at: now)
        #expect(store.items.count == 1)
        #expect(store.items[0].name == "invoice.pdf")
        #expect(store.items[0].byteCount == 42)
        #expect(store.items[0].kind == .document)
        #expect(!store.items[0].isCopy)
        #expect(store.items[0].url.standardizedFileURL == url.standardizedFileURL)
        #expect(space.copies().isEmpty)
    }

    @Test func copiesFilesWhenTheSettingSaysSo() async throws {
        let space = try Workspace()
        defer { space.finish() }
        var settings = ShelfSettings()
        settings.copiesFiles = true
        let store = space.store(settings)
        let url = try space.file("notes.md", bytes: 5)
        await store.add([url], at: now)
        let item = try #require(store.items.first)
        #expect(item.isCopy)
        #expect(item.path != url.standardizedFileURL.path)
        #expect(item.path.hasPrefix(space.shelfFolder.path(percentEncoded: false)))
        #expect(item.name == "notes.md")
        #expect(URL(filePath: item.path).lastPathComponent == "notes.md")
        #expect(FileManager.default.fileExists(atPath: item.path))
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func droppingTheSameFileAgainMovesItToTheFront() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let first = try space.file("a.txt")
        let second = try space.file("b.txt")
        await store.add([first, second], at: now)
        await store.add([first], at: now.addingTimeInterval(5))
        #expect(store.items.map(\.name) == ["a.txt", "b.txt"])
    }

    @Test func theOldestItemsDropOffAtTheLimit() async throws {
        let space = try Workspace()
        defer { space.finish() }
        var settings = ShelfSettings()
        settings.maxItems = 2
        let store = space.store(settings)
        for name in ["a", "b", "c"] {
            try await store.add([space.file(name)], at: now)
        }
        #expect(store.items.map(\.name) == ["c", "b"])
    }

    @Test func loweringTheLimitCutsTheList() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        try await store.add([space.file("a"), space.file("b"), space.file("c")], at: now)
        var settings = ShelfSettings()
        settings.maxItems = 1
        store.apply(settings)
        #expect(store.items.count == 1)
    }

    @Test func overflowDeletesTheCopyAndNeverTheOriginal() async throws {
        let space = try Workspace()
        defer { space.finish() }
        var settings = ShelfSettings()
        settings.copiesFiles = true
        settings.maxItems = 1
        let store = space.store(settings)
        let old = try space.file("old.txt")
        await store.add([old], at: now)
        try await store.add([space.file("new.txt")], at: now)
        await store.flush()
        #expect(space.copies().count == 1)
        #expect(FileManager.default.fileExists(atPath: old.path(percentEncoded: false)))
    }

    @Test func removingAReferenceLeavesTheFileAlone() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let url = try space.file("keep.txt")
        await store.add([url], at: now)
        try store.remove(#require(store.items.first))
        #expect(store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func clearAllDeletesCopiesOnly() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let reference = try space.file("ref.txt")
        await store.add([reference], at: now)
        var settings = ShelfSettings()
        settings.copiesFiles = true
        store.apply(settings)
        try await store.add([space.file("copied.txt")], at: now)
        #expect(space.copies().count == 1)
        store.clearAll()
        await store.flush()
        #expect(store.items.isEmpty)
        #expect(space.copies().isEmpty)
        #expect(FileManager.default.fileExists(atPath: reference.path(percentEncoded: false)))
    }

    @Test func theListSurvivesARestartAndDropsVanishedFiles() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let kept = try space.file("kept.txt")
        let gone = try space.file("gone.txt")
        await store.add([kept, gone], at: now)
        await store.flush()
        try FileManager.default.removeItem(at: gone)

        let reopened = space.store()
        #expect(reopened.items.isEmpty)
        await reopened.load()
        #expect(reopened.items.map(\.name) == ["kept.txt"])
    }

    @Test func refreshDropsFilesThatVanished() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        let gone = try space.file("gone.txt")
        try await store.add([gone, space.file("here.txt")], at: now)
        try FileManager.default.removeItem(at: gone)
        store.refresh()
        #expect(store.items.map(\.name) == ["here.txt"])
    }

    @Test func loadingRemovesCopiesThatNoItemOwns() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let stray = space.shelfFolder.appending(path: "Files/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        let store = space.store()
        await store.load()
        #expect(space.copies().isEmpty)
    }

    @Test func foldersAndNonFilesAreHandled() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        try await store.add(
            [space.userFolder, #require(URL(string: "https://example.com")), URL(filePath: "/no/such/file")],
            at: now
        )
        #expect(store.items.count == 1)
        #expect(store.items[0].kind == .folder)
    }

    @Test func settingsReadTheOptions() {
        #expect(ShelfSettings(options: [:]) == ShelfSettings())
        #expect(ShelfSettings().maxItems == 20)
        #expect(!ShelfSettings().copiesFiles)
        let custom = ShelfSettings(options: [
            ItemOption.shelfCopiesFiles: "true",
            ItemOption.shelfMaxItems: "50",
            ItemOption.shelfThumbnails: "false",
        ])
        #expect(custom.copiesFiles)
        #expect(custom.maxItems == 50)
        #expect(!custom.showsThumbnails)
    }

    @Test func changeIsReported() async throws {
        let space = try Workspace()
        defer { space.finish() }
        let store = space.store()
        var changes = 0
        store.onChange = { changes += 1 }
        try await store.add([space.file("a")], at: now)
        store.clearAll()
        #expect(changes == 2)
    }
}
