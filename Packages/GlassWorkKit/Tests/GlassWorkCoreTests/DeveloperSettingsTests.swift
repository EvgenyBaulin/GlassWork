import Foundation
@testable import GlassWorkCore
import Testing

struct DockerContextTests {
    @Test func readsContextsInOrder() throws {
        let contexts = try DockerParser.contexts(textFixture("docker-context-ls.jsonl"))
        #expect(contexts.map(\.name) == ["desktop-linux", "orbstack", "default", "build-box"])
        #expect(contexts.filter(\.isCurrent).map(\.name) == ["orbstack"])
        #expect(contexts[0].detail == "Docker Desktop")
        #expect(contexts[3].detail == "ssh://dev@build-box")
    }

    @Test func skipsLinesThatAreNotContexts() {
        #expect(DockerParser.contexts("garbage\n{\"Name\":\"\"}\n").isEmpty)
    }

    @Test func listsAndSwitchesThroughTheRunner() async throws {
        let listing = try textFixture("docker-context-ls.jsonl")
        let runner = FakeRunner { _, arguments in
            ProcessOutput(status: 0, stdout: arguments.contains("ls") ? listing : "", stderr: "")
        }
        let collector = DockerCollector(runner: runner, locate: { "/usr/local/bin/docker" })

        #expect(await collector.contexts().count == 4)
        #expect(await collector.use(context: "desktop-linux"))
        #expect(runner.calls.map { Array($0.dropFirst()) }
            == [["context", "ls", "--format", "json"], ["context", "use", "desktop-linux"]])
    }

    @Test func refusesNamesThatLookLikeOptions() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 0, stdout: "", stderr: "") }
        let collector = DockerCollector(runner: runner, locate: { "/usr/local/bin/docker" })

        #expect(await !collector.use(context: "--help"))
        #expect(await !collector.use(context: ""))
        #expect(runner.calls.isEmpty)
    }

    @Test func failedSwitchIsReported() async {
        let runner = FakeRunner { _, _ in ProcessOutput(status: 1, stdout: "", stderr: "no such context") }
        let collector = DockerCollector(runner: runner, locate: { "/usr/local/bin/docker" })
        #expect(await !collector.use(context: "gone"))
    }

    @Test func chosenBinaryWinsWhileItExists() {
        let found = DockerCLI.resolve(
            custom: "/opt/x/docker", find: { "/usr/local/bin/docker" }, check: { $0 == "/opt/x/docker" }
        )
        #expect(found == "/opt/x/docker")
        let gone = DockerCLI.resolve(custom: "/opt/x/docker", find: { "/usr/local/bin/docker" }, check: { _ in false })
        #expect(gone == "/usr/local/bin/docker")
        #expect(DockerCLI.resolve(custom: nil, find: { nil }) == nil)
    }
}

struct DeveloperChoiceOptionTests {
    @Test func openerAndDockerPathAreRead() {
        var settings = AppSettings()
        #expect(DeveloperOptions(settings: settings).devServerOpener == nil)
        #expect(DeveloperOptions(settings: settings).dockerPath == nil)
        settings.update(.devServers) { $0.options[DeveloperOptions.Key.openIn] = "com.apple.Safari" }
        settings.update(.docker) { $0.options[DeveloperOptions.Key.dockerPath] = "/opt/x/docker" }
        let options = DeveloperOptions(settings: settings)
        #expect(options.devServerOpener == "com.apple.Safari")
        #expect(options.dockerPath == "/opt/x/docker")
    }

    @Test func emptyChoiceMeansDefault() {
        var settings = AppSettings()
        settings.update(.devServers) { $0.options[DeveloperOptions.Key.openIn] = "" }
        #expect(DeveloperOptions(settings: settings).devServerOpener == nil)
    }

    @Test func removingAHandAddedRepository() {
        let list = ["/dev/a", "/dev/b", "/dev/c"]
        #expect(GitRepositoryList.removing("/dev/b", from: list) == ["/dev/a", "/dev/c"])
        #expect(GitRepositoryList.removing("/dev/none", from: list) == list)
        #expect(DeveloperOptions.encode(GitRepositoryList.removing("/dev/a", from: ["/dev/a"])) == nil)
    }
}

struct EndpointSettingsTests {
    @Test func oldSavedEndpointsGetDefaults() throws {
        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","url":"https://example.com","interval":120,"expectedStatus":204}"#
        let endpoint = try JSONDecoder().decode(Endpoint.self, from: Data(json.utf8))
        #expect(endpoint.id == id)
        #expect(endpoint.interval == 120)
        #expect(endpoint.expectedStatus == 204)
        #expect(endpoint.method == .get)
        #expect(endpoint.timeout == 10)
    }

    @Test func newFieldsSurviveARoundTrip() throws {
        var endpoint = try Endpoint(url: #require(URL(string: "https://example.com/health")))
        endpoint.method = .head
        endpoint.timeout = 4
        endpoint.interval = 30
        let copy = try JSONDecoder().decode(Endpoint.self, from: JSONEncoder().encode(endpoint))
        #expect(copy == endpoint)
    }

    @Test func unknownMethodFallsBackToGet() throws {
        let json = #"{"url":"https://example.com","method":"TRACE"}"#
        #expect(try JSONDecoder().decode(Endpoint.self, from: Data(json.utf8)).method == .get)
    }

    @Test func editedAndRemovedEndpointsStayInSettings() throws {
        var settings = AppSettings()
        var first = try Endpoint(url: #require(URL(string: "https://a.example")))
        let second = try Endpoint(url: #require(URL(string: "https://b.example")))
        settings.widgets.endpoints = [first, second]
        first.expectedStatus = 301
        settings.widgets.endpoints[0] = first
        settings.widgets.endpoints.remove(at: 1)
        let copy = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(copy.widgets.endpoints == [first])
    }

    @Test func dueOnlyAfterTheInterval() throws {
        var endpoint = try Endpoint(url: #require(URL(string: "https://a.example")))
        endpoint.interval = 300
        let last = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(endpoint.isDue(lastCheck: nil, at: last))
        #expect(!endpoint.isDue(lastCheck: last, at: last.addingTimeInterval(60)))
        #expect(endpoint.isDue(lastCheck: last, at: last.addingTimeInterval(300)))
    }
}
