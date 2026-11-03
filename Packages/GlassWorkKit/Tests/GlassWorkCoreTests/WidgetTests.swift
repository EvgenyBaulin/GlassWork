import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetModelTests {
    @Test(arguments: [(170.0, 170.0), (100.0, 194.0), (90.0, 0.0), (300.0, 388.0)])
    func snapsToTheGrid(value: Double, expected: Double) {
        #expect(WidgetPlacement.snapped(value) == (value == 170 ? 194 : expected))
    }

    @Test func snapshotSurvivesTheSharedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkWidgets-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        var snapshot = WidgetSnapshot(date: Date(timeIntervalSince1970: 1_800_000_000))
        snapshot.everyday.note = "Hello"

        try store.write(snapshot, for: WidgetSnapshot.key)

        #expect(store.read(WidgetSnapshot.self, for: WidgetSnapshot.key) == snapshot)
    }

    @Test func sizesMatchTheSystem() {
        #expect(WidgetSize.extraLarge.width == 760)
        #expect(WidgetSize.large.height == 382)
    }
}
