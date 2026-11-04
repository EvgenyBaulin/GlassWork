import Foundation
@testable import GlassWorkCore
import Testing

struct ToolLocatorTests {
    @Test func prefersHomebrew() {
        let found = ToolLocator.find("docker", home: "/Users/dev") { _ in true }
        #expect(found == "/opt/homebrew/bin/docker")
    }

    @Test func looksInTheToolsOwnFolders() {
        let found = ToolLocator.find("docker", home: "/Users/dev") { $0 == "/Users/dev/.orbstack/bin/docker" }
        #expect(found == "/Users/dev/.orbstack/bin/docker")
    }

    @Test func missingToolIsNil() {
        #expect(ToolLocator.find("docker", home: "/Users/dev") { _ in false } == nil)
    }

    @Test func gitStubIsNotUsedWithoutDeveloperTools() {
        #expect(ToolLocator.git(home: "/Users/dev") { $0 == "/usr/bin/git" } == nil)
    }

    @Test func gitStubIsUsedWithDeveloperTools() {
        let found = ToolLocator.git(home: "/Users/dev") { path in
            path == "/usr/bin/git" || path.hasPrefix("/Library/Developer/CommandLineTools")
        }
        #expect(found == "/usr/bin/git")
    }
}

struct DockerParserTests {
    @Test func readsContainers() throws {
        let containers = try DockerParser.containers(fixture("docker-ps.jsonl"))

        #expect(containers.map(\.name) == ["postgres-dev", "minio", "redis-cache", "worker"])
        #expect(containers.map(\.isRunning) == [true, true, true, false])
        #expect(containers[0].status == "Up 2 hours")
        #expect(containers[0].image == "postgres:16")
        #expect(containers[3].status == "Exited (0) 3 hours ago")
    }

    @Test func listsEachPublishedPortOnce() throws {
        let containers = try DockerParser.containers(fixture("docker-ps.jsonl"))

        #expect(containers[0].ports == ["5432→5432"])
        #expect(containers[1].ports == ["9000-9001"])
    }

    @Test func differentHostPortShowsBothSides() {
        #expect(DockerParser.ports("127.0.0.1:8080->80/tcp") == ["8080→80"])
    }

    @Test func unpublishedPortsAreLeftOut() {
        #expect(DockerParser.ports("6379/tcp").isEmpty)
        #expect(DockerParser.ports("").isEmpty)
    }

    @Test func skipsLinesItCannotRead() {
        #expect(DockerParser.containers("{\"ID\":\"1\"}\nnot json\n").isEmpty)
    }

    @Test func daemonOff() {
        let stderr = """
        Cannot connect to the Docker daemon at unix:///Users/dev/.docker/run/docker.sock. \
        Is the docker daemon running?

        """
        #expect(DockerParser.reading(ProcessOutput(status: 1, stdout: "", stderr: stderr)) == .notRunning)
    }

    @Test func socketRefused() {
        let stderr = """
        permission denied while trying to connect to the docker API at unix:///Users/dev/.docker/run/docker.sock

        """
        #expect(DockerParser.reading(ProcessOutput(status: 1, stdout: "", stderr: stderr)) == .permissionDenied)
    }

    @Test func otherErrorsAreShown() {
        let output = ProcessOutput(status: 1, stdout: "", stderr: "context \"x\" does not exist\nmore\n")
        #expect(DockerParser.reading(output) == .failed("context \"x\" does not exist"))
    }

    @Test func noCLIMeansNotInstalled() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: "", stderr: "") }

        #expect(await DockerCollector(runner: runner, locate: { nil }).read() == .notInstalled)
        #expect(runner.calls.isEmpty)
    }

    @Test func runsOnlyReadOnlyCommands() async throws {
        let listing = try fixture("docker-ps.jsonl")
        let runner = FakeRunner { _, arguments in
            ProcessOutput(status: 0, stdout: arguments.first == "ps" ? listing : "orbstack\n", stderr: "")
        }

        let reading = await DockerCollector(runner: runner, locate: { "/usr/local/bin/docker" }).read()

        #expect(reading.containers.count == 4)
        if case let .containers(_, context) = reading {
            #expect(context == "orbstack")
        }
        #expect(runner.calls.map { Array($0.dropFirst()) } == [["ps", "-a", "--format", "json"], ["context", "show"]])
    }
}

struct DevServerParserTests {
    private let home = "/Users/dev"

    private func servers() throws -> [DevServer] {
        try DevServerFilter.servers(
            sockets: DevServerParser.sockets(fixture("lsof-listen.txt")),
            directories: DevServerParser.workingDirectories(fixture("lsof-cwd.txt")),
            processes: DevServerParser.processes(fixture("ps-processes.txt")),
            home: home
        )
    }

    @Test func mergesIPv4AndIPv6() throws {
        let sockets = try DevServerParser.sockets(fixture("lsof-listen.txt"))
        #expect(sockets.count { $0.port == 3000 } == 1)
        #expect(sockets.count { $0.port == 57414 } == 1)
    }

    @Test func readsWorkingDirectories() throws {
        let directories = try DevServerParser.workingDirectories(fixture("lsof-cwd.txt"))
        #expect(directories[1041] == "/")
        #expect(directories[60210] == "/Users/dev/Developer/pocket-api")
    }

    @Test func leavesOutAppsAndDaemons() throws {
        #expect(try servers().map(\.port) == [3000, 5432, 9090, 38123])
    }

    @Test func describesAWebServer() throws {
        let server = try #require(try servers().first)

        #expect(server.process == "node")
        #expect(server.tool == "next dev")
        #expect(server.project == "pocket-api")
        #expect(server.uptime == 7391)
        #expect(server.url?.absoluteString == "http://localhost:3000")
    }

    @Test func databasesHaveAnAddressButNoBrowserLink() throws {
        let server = try #require(try servers().first { $0.port == 5432 })

        #expect(server.kind == .service)
        #expect(server.url == nil)
        #expect(server.copyText == "localhost:5432")
        #expect(server.uptime == 273_906)
    }

    @Test func folderRightInHomeKeepsItsPath() throws {
        let server = try #require(try servers().first { $0.port == 38123 })

        #expect(server.project == "~/Downloads")
        #expect(server.tool == "http.server")
    }

    @Test func nothingFromTheCommandLineIsKeptButTheToolName() throws {
        let details = try DevServerParser.processes(fixture("ps-processes.txt"))
        #expect(!"\(details)".contains("hunter2"))
    }

    @Test(arguments: [("00:02", 2.0), ("03:12", 192.0), ("01:02:03", 3723.0), ("2-00:00:01", 172_801.0)])
    func parsesElapsedTime(text: String, seconds: TimeInterval) {
        #expect(DevServerParser.elapsed(text) == seconds)
    }

    @Test func rejectsBadElapsedTime() {
        #expect(DevServerParser.elapsed("soon") == nil)
    }

    @Test func aKnownToolOnASystemPortStillCounts() {
        let servers = DevServerFilter.servers(
            sockets: [ListeningSocket(pid: 1, command: "node", port: 60000)],
            directories: [1: "/Users/dev/Developer/app"],
            processes: [1: ProcessDetails(uptime: nil, tool: "vite")],
            home: home
        )
        #expect(servers.count == 1)
    }

    @Test func aRuntimeInTheRootFolderIsNotADevServer() {
        let servers = DevServerFilter.servers(
            sockets: [ListeningSocket(pid: 1, command: "node", port: 8000)],
            directories: [1: "/"],
            processes: [:],
            home: home
        )
        #expect(servers.isEmpty)
    }

    @Test func nothingListening() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "") }

        #expect(await DevServerCollector(runner: runner, home: home).read() == .servers([]))
        #expect(runner.calls.count == 1)
    }

    @Test func lsofErrorIsReported() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "lsof: bad\n") }
        #expect(await DevServerCollector(runner: runner, home: home).read() == .failed)
    }

    @Test func looksUpEveryProcessInOneCall() async throws {
        let listing = try fixture("lsof-listen.txt")
        let runner = FakeRunner { tool, arguments in
            let isListing = tool.hasSuffix("lsof") && arguments.first == "-nP"
            return ProcessOutput(status: 0, stdout: isListing ? listing : "", stderr: "")
        }

        _ = await DevServerCollector(runner: runner, home: home).read()

        #expect(runner.calls.count == 3)
    }
}
