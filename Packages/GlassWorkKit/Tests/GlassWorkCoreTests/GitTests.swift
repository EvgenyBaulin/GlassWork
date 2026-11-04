import Foundation
@testable import GlassWorkCore
import Testing

struct GitStatusParserTests {
    @Test func countsChangesAheadAndBehind() throws {
        let status = try GitStatusParser.parse(fixture("git-status-ahead-behind.txt"))

        #expect(status.branch == "main")
        #expect(status.upstream == "origin/main")
        #expect(status.ahead == 1)
        #expect(status.behind == 1)
        #expect(status.changed == 3)
        #expect(!status.isClean)
    }

    @Test func countsConflictsApart() throws {
        let status = try GitStatusParser.parse(fixture("git-status-conflict.txt"))

        #expect(status.conflicted == 1)
        #expect(status.changed == 0)
        #expect(status.ahead == 1)
        #expect(status.behind == 0)
    }

    @Test func detachedHeadShowsTheShortHash() throws {
        let status = try GitStatusParser.parse(fixture("git-status-detached.txt"))

        #expect(status.branch == nil)
        #expect(status.head == "0776d55")
        #expect(status.isClean)
    }

    @Test func aNewRepositoryHasNoCommit() throws {
        let status = try GitStatusParser.parse(fixture("git-status-initial.txt"))

        #expect(status.commit == nil)
        #expect(status.head == "main")
        #expect(status.upstream == nil)
    }

    @Test func readsTheCommitDate() {
        #expect(GitStatusParser.commitDate("1793770723\n") == Date(timeIntervalSince1970: 1_793_770_723))
        #expect(GitStatusParser.commitDate("") == nil)
    }
}

struct GitChangeFilterTests {
    private let repositories = ["/dev/app", "/dev/tools/cli"]

    @Test func findsTheRepositoryOfAChange() {
        let changed = ["/dev/app/Sources/", "/dev/tools/cli/.git"]
        #expect(GitChangeFilter.repositories(changed: changed, in: repositories) == ["/dev/app", "/dev/tools/cli"])
    }

    @Test(arguments: [
        "/dev/app/build/Intermediates",
        "/dev/app/node_modules/x",
        "/dev/app/.build/debug",
        "/dev/app/.git/objects/ab",
        "/dev/app/.cache",
        "/dev/other/file",
    ])
    func ignoresNoise(path: String) {
        #expect(GitChangeFilter.repositories(changed: [path], in: repositories).isEmpty)
    }

    @Test func aFolderWithTheSamePrefixIsAnotherRepository() {
        #expect(GitChangeFilter.repositories(changed: ["/dev/app-two/x"], in: repositories).isEmpty)
    }
}

struct ProtectedFoldersTests {
    @Test(arguments: [
        "/Users/dev/Documents/app",
        "/Users/dev/Desktop",
        "/Users/dev/Downloads/x",
        "/Users/dev/Library/Mobile Documents/x",
        "/Volumes/USB/app",
    ])
    func protected(path: String) {
        #expect(ProtectedFolders.contains(path, home: "/Users/dev"))
    }

    @Test(arguments: ["/Users/dev/Developer/app", "/Users/dev/Documents-old/app", "/opt/app"])
    func notProtected(path: String) {
        #expect(!ProtectedFolders.contains(path, home: "/Users/dev"))
    }
}

struct GitDiscoveryTests {
    private func makeTree(_ paths: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for path in paths {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        return root
    }

    @Test func findsRepositoriesOneAndTwoLevelsDown() throws {
        let root = try makeTree(["one/.git", "group/two/.git", "group/deep/er/.git", "plain/src"])
        defer { try? FileManager.default.removeItem(at: root) }

        let names = GitDiscovery.repositories(in: root.path).map { URL(filePath: $0).lastPathComponent }

        #expect(names == ["two", "one"])
    }

    @Test func doesNotDescendIntoARepositoryOrHiddenFolders() throws {
        let root = try makeTree(["one/.git", "one/nested/.git", ".hidden/x/.git", "group/node_modules/.git"])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(GitDiscovery.repositories(in: root.path).count == 1)
    }

    @Test func aMissingRootIsEmpty() {
        #expect(GitDiscovery.repositories(in: "/no/such/folder").isEmpty)
    }
}

struct GitCollectorTests {
    private func home(_ repositories: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for path in repositories {
            try FileManager.default.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        return root
    }

    private func runner() throws -> FakeRunner {
        let status = try fixture("git-status-ahead-behind.txt")
        return FakeRunner { _, arguments in
            ProcessOutput(status: 0, stdout: arguments.contains("status") ? status : "1793770723\n", stderr: "")
        }
    }

    @Test func runsOnlyReadOnlyCommandsWithoutLocks() async throws {
        let home = try home(["Developer/app/.git"])
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = try runner()
        let collector = GitCollector(runner: runner, home: home.path) { "/usr/bin/git" }

        let reading = await collector.read(manual: [])

        #expect(reading.repositories.count == 1)
        #expect(reading.repositories[0].status?.changed == 3)
        #expect(runner.calls.count == 2)
        for call in runner.calls {
            #expect(call[1] == "--no-optional-locks")
            #expect(call.contains("core.fsmonitor=false"))
            #expect(call.contains("status") || call.contains("log"))
            #expect(!call.contains("fetch") && !call.contains("commit") && !call.contains("push"))
        }
    }

    @Test func protectedFoldersAreNeverTouched() async throws {
        let home = try home(["Developer"])
        defer { try? FileManager.default.removeItem(at: home) }
        let runner = try runner()
        let collector = GitCollector(runner: runner, home: home.path) { "/usr/bin/git" }

        let reading = await collector.read(manual: [home.path + "/Documents/app"])

        #expect(reading.repositories.first?.problem == .needsPermission)
        #expect(runner.calls.isEmpty)
    }

    @Test func aFolderThatLostItsRepositoryIsReported() async throws {
        let home = try home(["Developer"])
        defer { try? FileManager.default.removeItem(at: home) }
        let collector = try GitCollector(runner: runner(), home: home.path) { "/usr/bin/git" }

        let reading = await collector.read(manual: ["/no/such/repository"])

        #expect(reading.repositories.first?.problem == .missing)
        #expect(reading.repositories.first?.isManual == true)
    }

    @Test func noGitMeansNotInstalled() async throws {
        let collector = try GitCollector(runner: runner(), home: "/Users/dev") { nil }
        #expect(await collector.read(manual: []) == .notInstalled)
    }
}

struct GitReadingTests {
    private func repository(_ path: String, age: TimeInterval, problem: GitProblem? = nil) -> GitRepository {
        GitRepository(
            path: path,
            status: problem == nil ? GitStatus() : nil,
            lastCommit: Date(timeIntervalSince1970: 1_800_000_000 - age),
            problem: problem
        )
    }

    @Test func recentRepositoriesComeFirstAndBrokenOnesLast() {
        let sorted = GitRepository.sorted([
            repository("/old", age: 100),
            repository("/broken", age: 0, problem: .missing),
            repository("/new", age: 1),
        ])
        #expect(sorted.map(\.path) == ["/new", "/old", "/broken"])
    }

    @Test func theChosenRepositoryWins() {
        let reading = GitReading.repositories([repository("/new", age: 1), repository("/old", age: 100)])

        #expect(reading.selected(path: "/old")?.path == "/old")
        #expect(reading.selected(path: nil)?.path == "/new")
        #expect(reading.selected(path: "/gone")?.path == "/new")
    }

    @Test func updatesOnlyWhatChanged() {
        var fresh = repository("/old", age: 0)
        fresh.status?.changed = 4
        let reading = GitReading.repositories([repository("/new", age: 1), repository("/old", age: 100)])

        let updated = reading.updating([fresh])

        #expect(updated.repositories.map(\.path) == ["/old", "/new"])
        #expect(updated.repositories[0].status?.changed == 4)
    }
}

struct RepositoryOptionTests {
    @Test func listRoundTrips() {
        let paths = ["/a/one", "/b/two words"]
        #expect(DeveloperOptions.decode(DeveloperOptions.encode(paths)) == paths)
    }

    @Test func emptyListRemovesTheOption() {
        #expect(DeveloperOptions.encode([]) == nil)
        #expect(DeveloperOptions.decode(nil).isEmpty)
    }

    @Test func readsTheChoiceFromSettings() {
        var settings = AppSettings()
        settings.update(.git) {
            $0.options[DeveloperOptions.Key.repository] = "/a/one"
            $0.options[DeveloperOptions.Key.repositories] = "/a/one\n/b/two"
        }
        let options = DeveloperOptions(settings: settings)

        #expect(options.gitRepository == "/a/one")
        #expect(options.gitRepositories == ["/a/one", "/b/two"])
    }
}

@MainActor
struct GitStoreTests {
    private func wait(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aChangeRereadsOnlyThatRepositoryAtTheNextTick() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for name in ["one", "two"] {
            try FileManager.default.createDirectory(
                at: root.appending(path: "Developer/\(name)/.git"),
                withIntermediateDirectories: true
            )
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let status = try fixture("git-status-detached.txt")
        let runner = FakeRunner { _, arguments in
            ProcessOutput(status: 0, stdout: arguments.contains("status") ? status : "", stderr: "")
        }
        let store = DeveloperStore(runner: runner, home: root.path, locateGit: { "/usr/bin/git" })
        let start = Date()
        store.tick(at: start, demand: [.git])
        await wait { store.git != nil }
        let first = runner.calls.count
        let changed = try #require(store.git?.repositories.first?.path)

        store.repositoriesChanged([changed + "/Sources"])
        store.tick(at: start.addingTimeInterval(1), demand: [.git])
        await wait { runner.calls.count == first + 2 && store.isIdle(.git) }
        let reread = runner.calls.dropFirst(first)
        #expect(reread.count == 2)
        #expect(reread.allSatisfy { $0.contains(changed) })

        // A burst of changes waits, so a running build cannot keep git busy.
        store.repositoriesChanged([changed + "/Sources"])
        store.tick(at: start.addingTimeInterval(3), demand: [.git])
        try? await Task.sleep(for: .milliseconds(30))
        #expect(runner.calls.count == first + 2)

        store.tick(at: start.addingTimeInterval(6.5), demand: [.git])
        await wait { runner.calls.count == first + 4 && store.isIdle(.git) }
        #expect(runner.calls.count == first + 4)
        store.tick(at: start.addingTimeInterval(7), demand: [])
    }
}
