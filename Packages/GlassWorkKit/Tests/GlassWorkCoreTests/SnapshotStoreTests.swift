import Foundation
@testable import GlassWorkCore
import Testing

struct SnapshotStoreTests {
    @Test func roundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        let beat = Heartbeat(
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            bootTime: Date(timeIntervalSince1970: 1_799_000_000)
        )

        try store.write(beat, for: Heartbeat.key)

        #expect(store.read(Heartbeat.self, for: Heartbeat.key) == beat)
    }

    @Test func missingKeyReturnsNil() {
        let store = SnapshotStore(directory: URL(filePath: "/nonexistent-\(UUID().uuidString)"))
        #expect(store.read(Heartbeat.self, for: "nothing") == nil)
    }

    @Test func bootTimeIsInThePast() throws {
        let boot = try #require(SystemClock.bootTime())
        #expect(boot < Date())
    }
}
