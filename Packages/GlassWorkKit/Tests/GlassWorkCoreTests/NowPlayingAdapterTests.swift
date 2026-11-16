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

    private final class LockedValue<Value: Sendable>: @unchecked Sendable {
        // Why unchecked: the lock guards the value.
        private let lock = NSLock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func set(_ new: Value) {
            lock.withLock { value = new }
        }

        func get() -> Value {
            lock.withLock { value }
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

    @Test func everyLineArrivesBeforeTheExitIsReported() async {
        // Many short-lived children at once: the exit often races the last read of the output.
        let runs = 60
        let results = await withTaskGroup(of: Bool.self) { group in
            for index in 0 ..< runs {
                group.addTask {
                    let adapter = NowPlayingAdapter(executable: "/bin/sh", arguments: ["-c", "echo line-\(index)"])
                    let collector = Collector()
                    let linesAtExit = LockedValue<[String]>([])
                    do {
                        try adapter.start(
                            onLine: collector.add,
                            onExit: { status in
                                linesAtExit.set(collector.received)
                                collector.finish(status)
                            }
                        )
                    } catch {
                        return false
                    }
                    try? await wait { collector.exitStatus != nil }
                    adapter.stop()
                    return collector.exitStatus == 0 && linesAtExit.get() == ["line-\(index)"]
                }
            }
            return await group.reduce(into: 0) { $0 += $1 ? 1 : 0 }
        }
        #expect(results == runs, "complete runs: \(results) of \(runs)")
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
