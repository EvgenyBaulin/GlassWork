import Foundation
@testable import GlassWorkCore
import Testing

struct GitOperationTests {
    private func repository(_ files: [String] = [], gitFile: String? = nil) throws -> String {
        let root = FileManager.default.temporaryDirectory.appending(path: "gw-op-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let gitFile {
            try gitFile.write(to: root.appending(path: ".git"), atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.createDirectory(at: root.appending(path: ".git"), withIntermediateDirectories: true)
        }
        for file in files {
            let url = root.appending(path: file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
        return root.path(percentEncoded: false)
    }

    @Test func anOrdinaryRepositoryHasNoOperation() throws {
        #expect(try GitOperationReader.read(repository: repository()) == nil)
    }

    @Test func mergeHeadMeansAMerge() throws {
        #expect(try GitOperationReader.read(repository: repository([".git/MERGE_HEAD"])) == .merge)
    }

    @Test func rebaseFoldersMeanARebase() throws {
        #expect(try GitOperationReader.read(repository: repository([".git/rebase-merge/head-name"])) == .rebase)
        #expect(try GitOperationReader.read(repository: repository([".git/rebase-apply/next"])) == .rebase)
    }

    @Test func aLinkedWorktreeFollowsItsGitdirFile() throws {
        let real = try repository([".git/MERGE_HEAD"])
        let linked = try repository(gitFile: "gitdir: \(real)/.git\n")
        #expect(GitOperationReader.read(repository: linked) == .merge)
    }

    @Test func aRelativeGitdirIsResolvedFromTheRepository() throws {
        let linked = try repository(["real/MERGE_HEAD"], gitFile: "gitdir: real\n")
        #expect(GitOperationReader.read(repository: linked) == .merge)
    }

    @Test func aMissingRepositoryHasNoOperation() {
        #expect(GitOperationReader.read(repository: "/nonexistent-gw-folder") == nil)
    }

    @Test func aStatusWithoutConflictsCanStillHaveAnOperation() {
        var status = GitStatus()
        status.operation = .merge
        #expect(status.isClean)
        #expect(status.conflicted == 0)
        #expect(status.operation == .merge)
    }
}
