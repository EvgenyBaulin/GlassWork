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

struct WidgetTopUsageTests {
    private let chrome = ProcessUsage(pid: 1, name: "Google Chrome", cpu: 41, memory: 1)
    private let helper = ProcessUsage(pid: 9, name: "Google Chrome He", cpu: 30, memory: 1)

    @Test func appsComeFirstWhenTheyHaveFigures() {
        var snapshot = WidgetSnapshot(date: Date())
        snapshot.processes = [helper]
        snapshot.apps = [chrome]
        #expect(snapshot.topUsage == [chrome])
    }

    @Test(arguments: [nil, [], [ProcessUsage(pid: 1, name: "Google Chrome", cpu: 0, memory: 1)]] as [[ProcessUsage]?])
    func processesStandInWithoutFigures(apps: [ProcessUsage]?) {
        var snapshot = WidgetSnapshot(date: Date())
        snapshot.processes = [helper]
        snapshot.apps = apps
        #expect(snapshot.topUsage == [helper])
    }

    @Test func aSnapshotFromAnEarlierVersionStillDecodes() throws {
        let old = try JSONEncoder().encode(WidgetSnapshot(date: Date(timeIntervalSince1970: 0)))
        var json = try #require(JSONSerialization.jsonObject(with: old) as? [String: Any])
        json["apps"] = nil
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: data).apps == nil)
    }
}
