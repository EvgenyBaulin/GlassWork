import Foundation
@testable import GlassWorkCore
import Testing

/// A saved response from `Tests/GlassWorkCoreTests/Fixtures`.
func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil))
    return try Data(contentsOf: url)
}

/// A folder of its own for each test, so nothing touches the user's real files.
func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(
        path: "GlassWorkTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
}

/// Answers from a table and records what was asked. Nothing here reaches the network.
final class FakeFetcher: HTTPFetching, @unchecked Sendable {
    // @unchecked: the lock below guards `requested`, and the table never changes after init.
    private let lock = NSLock()
    private var requested: [URL] = []
    private let answer: @Sendable (URL) throws -> Data

    init(answer: @escaping @Sendable (URL) throws -> Data) {
        self.answer = answer
    }

    var requests: [URL] {
        lock.withLock { requested }
    }

    func data(from url: URL) async throws -> Data {
        lock.withLock { requested.append(url) }
        return try answer(url)
    }
}
