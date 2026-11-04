import Foundation
@testable import GlassWorkCore
import Testing

/// Text of a real command output saved in `Fixtures`.
func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

/// Answers each command from a table keyed by the tool's file name, and remembers every call.
final class FakeRunner: ProcessRunning, @unchecked Sendable {
    // Why unchecked: the lock below guards `calls`, the only mutable state.
    private let lock = NSLock()
    private var recorded: [[String]] = []
    private let answer: @Sendable (String, [String]) throws -> ProcessOutput

    init(answer: @escaping @Sendable (String, [String]) throws -> ProcessOutput) {
        self.answer = answer
    }

    var calls: [[String]] {
        lock.withLock { recorded }
    }

    func run(_ executable: String, arguments: [String], timeout _: TimeInterval) async throws -> ProcessOutput {
        lock.withLock { recorded.append([executable] + arguments) }
        return try answer(executable, arguments)
    }
}
