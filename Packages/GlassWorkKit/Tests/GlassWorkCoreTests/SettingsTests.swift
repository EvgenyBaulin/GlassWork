import Foundation
@testable import GlassWorkCore
import Testing

@MainActor
struct SettingsTests {
    private func temporaryFile() -> SettingsFile {
        SettingsFile(url: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkSettings-\(UUID().uuidString)/settings.json"))
    }

    @Test func defaultsPutThreeModulesInTheMenuBar() {
        let enabled = AppSettings().modules.filter { $0.mode == .menuBar }.map(\.id)
        #expect(enabled == [.overview, .cpu, .memory])
        #expect(AppSettings().modules.count == ModuleID.allCases.count)
    }

    @Test func roundTripsThroughTheFile() throws {
        let file = temporaryFile()
        var settings = AppSettings()
        settings.update(.gpu) { $0.mode = .menuBar }
        settings.numberStyle = .precise

        try file.save(settings)

        #expect(try file.load() == settings)
    }

    @Test func keepsUnknownKeysOnSave() throws {
        let file = temporaryFile()
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"futureKey": 1, "hiding": {"futureNested": true}}"#.utf8).write(to: file.url)

        try file.save(AppSettings())

        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
        #expect(object["futureKey"] as? Int == 1)
        let hiding = try #require(object["hiding"] as? [String: Any])
        #expect(hiding["futureNested"] as? Bool == true)
        #expect(hiding["autoHideSeconds"] as? Int == 10)
    }

    @Test func fillsInModulesMissingFromAnOlderFile() throws {
        let json = #"{"modules": [{"id": "cpu", "mode": "off", "style": "figure", "options": {}},"#
            + #" {"id": "fromTheFuture", "mode": "off", "style": "figure", "options": {}}]}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        #expect(settings.module(.cpu)?.mode == .off)
        #expect(settings.modules.first?.id == .cpu)
        #expect(settings.modules.count == ModuleID.allCases.count)
    }

    @Test func storeSavesChanges() throws {
        let file = temporaryFile()
        let store = SettingsStore(file: file)

        store.update { $0.update(.disk) { $0.mode = .menuBar } }

        #expect(try file.load()?.module(.disk)?.mode == .menuBar)
    }
}

struct FormatTests {
    @Test func formatsPercent() {
        #expect(Format.percent(0.234) == "23%")
        #expect(Format.percent(0.234, style: .precise) == "23.4%")
    }

    @Test func formatsBytes() {
        #expect(Format.bytes(1_230_000_000) == "1.2G")
        #expect(Format.bytes(214_000_000_000) == "214G")
        #expect(Format.bytes(1_230_000_000, style: .precise) == "1.23 GB")
    }

    @Test func formatsRates() {
        #expect(Format.rate(12_400_000) == "12M/s")
        #expect(Format.rate(2_400_000, style: .precise) == "2.4 MB/s")
    }
}

struct HistoryTests {
    @Test func dropsOldestWhenFull() {
        var history = History<Int>(capacity: 3)
        for value in 1 ... 5 {
            history.append(value, at: Date(timeIntervalSince1970: Double(value)))
        }
        #expect(history.points.map(\.value) == [3, 4, 5])
        #expect(history.latest?.value == 5)
    }

    @Test func tiersAverageIntoCoarserRanges() {
        var history = TieredHistory()
        let start = Date(timeIntervalSince1970: 1000)
        for second in stride(from: 0, through: 12, by: 2) {
            history.append(Double(second), at: start.addingTimeInterval(Double(second)))
        }
        let now = start.addingTimeInterval(12)
        #expect(history.points(in: .minute, now: now).count == 7)
        #expect(history.points(in: .hour, now: now).map(\.value) == [5])
    }
}
