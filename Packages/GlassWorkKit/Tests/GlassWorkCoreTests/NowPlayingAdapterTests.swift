import Foundation
@testable import GlassWorkCore
import Testing

/// The real process wrapper around ordinary system tools. No media is involved.
struct NowPlayingAdapterTests {
    private final class Collector: @unchecked Sendable {
        // Why unchecked: the lock guards both values.
        private let lock = NSLock()
        private var lines: [String] = []
        private var status: Int32?

        func add(_ line: String) {
            lock.withLock { lines.append(line) }
        }

        func finish(_ value: Int32) {
            lock.withLock { status = value }
        }

        var received: [String] {
            lock.withLock { lines }
        }

        var exitStatus: Int32? {
            lock.withLock { status }
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 3000 where !condition() { // 30 s: right after a build, Perl can take seconds to start
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func linesGoInAndComeBack() async throws {
        let adapter = NowPlayingAdapter(executable: "/bin/cat", arguments: [])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        adapter.send("toggle")
        try await wait { !collector.received.isEmpty }
        #expect(collector.received == ["toggle"])
        adapter.stop()
    }

    @Test func theExitStatusIsReported() async throws {
        let adapter = NowPlayingAdapter(executable: "/bin/sh", arguments: ["-c", "exit 3"])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        try await wait { collector.exitStatus != nil }
        #expect(collector.exitStatus == 3)
    }

    @Test func writingToADeadProcessDoesNotKillTheApp() async throws {
        let adapter = NowPlayingAdapter(executable: "/usr/bin/true", arguments: [])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        try await wait { collector.exitStatus != nil }
        adapter.send("toggle")
        adapter.send("toggle")
        adapter.stop()
    }

    @Test func perlGetsAMinimalEnvironment() async throws {
        let code = #"print join(",", sort grep { !/^__CF/ } keys %ENV), "\n""#
        let adapter = NowPlayingAdapter(executable: "/usr/bin/perl", arguments: ["-e", code])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        // Both the line and the exit: a failure then says whether Perl hung or its output was lost.
        try await wait { !collector.received.isEmpty && collector.exitStatus != nil }
        #expect(collector.exitStatus == 0)
        #expect(collector.received == ["LANG,PATH"], "lines: \(collector.received)")
        // The output handler holds the adapter weakly, so it must outlive the read.
        adapter.stop()
    }

    @Test func theScriptCompiles() async throws {
        let script = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../App/Resources/now-playing-adapter.pl")
            .standardized
        let output = try await ProcessRunner().run("/usr/bin/perl", arguments: ["-c", script.path], timeout: 20)
        #expect(output.status == 0)
        #expect(output.stderr.contains("syntax OK"))
    }
}
