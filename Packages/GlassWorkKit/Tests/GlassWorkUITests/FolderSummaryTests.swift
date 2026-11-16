import Foundation
@testable import GlassWorkUI
import Testing

struct FolderSummaryTests {
    @Test func countsItemsAndAddsUpFilesOneLevelDown() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appending(path: "inner"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(count: 100).write(to: folder.appending(path: "a.bin"))
        try Data(count: 50).write(to: folder.appending(path: "b.bin"))
        try Data(count: 999).write(to: folder.appending(path: "inner/deep.bin"))
        try Data(count: 7).write(to: folder.appending(path: ".hidden"))

        let summary = FolderSummary(path: folder.path)

        #expect(summary == FolderSummary(count: 3, bytes: 150, isPartial: false))
    }

    @Test func aMissingFolderIsEmpty() {
        #expect(FolderSummary(path: "/no/such/folder") == FolderSummary(count: 0, bytes: 0, isPartial: false))
    }
}
