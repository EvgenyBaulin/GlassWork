import Foundation
@testable import GlassWorkCore
import Testing

struct LineSessionRunnerTests {
    private let runner = LineSessionRunner()

    @Test func returnsTheMatchingLine() async throws {
        let line = try await runner.exchange(
            "/bin/cat",
            arguments: [],
            send: ["a", "b", "c"],
            until: { $0 == "b" },
            timeout: 5
        )
        #expect(line == "b")
    }

    @Test func timesOutAndStopsTheChild() async throws {
        let started = Date()
        await #expect(throws: ProcessRunnerError.timedOut("/bin/sleep")) {
            try await runner.exchange("/bin/sleep", arguments: ["37"], send: [], until: { _ in true }, timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(started) < 3)
        try await Task.sleep(for: .milliseconds(300))
        let check = Process()
        check.executableURL = URL(filePath: "/usr/bin/pgrep")
        check.arguments = ["-f", "^/bin/sleep 37$"]
        check.standardOutput = FileHandle.nullDevice
        try check.run()
        check.waitUntilExit()
        #expect(check.terminationStatus == 1)
    }

    @Test func endsWithoutAnswer() async {
        await #expect(throws: ProcessRunnerError.endedWithoutAnswer("/usr/bin/true")) {
            try await runner.exchange("/usr/bin/true", arguments: [], send: ["x"], until: { _ in true }, timeout: 5)
        }
    }

    @Test func aMissingToolIsNotFound() async {
        await #expect(throws: ProcessRunnerError.notFound("/no/such/tool")) {
            try await runner.exchange("/no/such/tool", arguments: [], send: [], until: { _ in true }, timeout: 1)
        }
    }
}
