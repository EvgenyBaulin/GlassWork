import Foundation
@testable import GlassWorkCore
import Testing

/// Hand edits of settings.json, by every way an editor can save.
@MainActor
struct SettingsWatchTests {
    private func file() -> SettingsFile {
        SettingsFile(url: temporaryFolder().appending(path: "settings.json"))
    }

    private func encoded(_ change: (inout AppSettings) -> Void) throws -> Data {
        var settings = AppSettings()
        change(&settings)
        return try JSONEncoder().encode(settings)
    }

    /// What `nano` and `open(path, "w")` do: the same file, cut to nothing and written again.
    private func writeInPlace(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try handle.close()
    }

    /// The store hears about changes on the main queue, so the test has to let go of it while waiting.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 200 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func anInPlaceWriteIsPickedUp() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)

        try writeInPlace(encoded { $0.numberStyle = .precise }, to: file.url)
        try await waitUntil { store.settings.numberStyle == .precise }

        #expect(store.settings.numberStyle == .precise)
    }

    /// The store saves by replacing the file, which leaves a watch on the old file looking at nothing.
    @Test func anInPlaceWriteIsPickedUpAfterTheStoreSavedItself() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)
        store.update { $0.keepsDiagnosticLog = true }
        try await Task.sleep(for: .milliseconds(100))

        try writeInPlace(encoded { $0.numberStyle = .precise }, to: file.url)
        try await waitUntil { store.settings.numberStyle == .precise }

        #expect(store.settings.numberStyle == .precise)
    }

    @Test func manyInPlaceWritesKeepWorking() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)

        for round in 1 ... 3 {
            let seconds = 5 + round
            try writeInPlace(encoded { $0.hiding.autoHideSeconds = seconds }, to: file.url)
            try await waitUntil { store.settings.hiding.autoHideSeconds == seconds }
            #expect(store.settings.hiding.autoHideSeconds == seconds)
            store.update { $0.update(.gpu) { $0.options["round"] = String(round) } }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func anAtomicReplaceIsStillPickedUp() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)

        try encoded { $0.numberStyle = .precise }.write(to: file.url, options: .atomic)
        try await waitUntil { store.settings.numberStyle == .precise }

        #expect(store.settings.numberStyle == .precise)
    }

    @Test func aFileCreatedAfterLaunchIsWatchedToo() async throws {
        let file = file()
        let store = SettingsStore(file: file)
        try FileManager.default.createDirectory(
            at: file.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try file.save(AppSettings())
        try await Task.sleep(for: .milliseconds(100))

        try writeInPlace(encoded { $0.numberStyle = .precise }, to: file.url)
        try await waitUntil { store.settings.numberStyle == .precise }

        #expect(store.settings.numberStyle == .precise)
    }

    @Test func aBrokenEditKeepsTheSettingsAndSaysSo() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)
        store.update { $0.numberStyle = .precise }
        try await Task.sleep(for: .milliseconds(100))

        try writeInPlace(Data("{ not json".utf8), to: file.url)
        try await waitUntil { store.lastError != nil }

        #expect(store.lastError != nil)
        #expect(store.settings.numberStyle == .precise)
    }

    @Test func fixingABrokenEditClearsTheError() async throws {
        let file = file()
        try file.save(AppSettings())
        let store = SettingsStore(file: file)
        try writeInPlace(Data("{ not json".utf8), to: file.url)
        try await waitUntil { store.lastError != nil }

        try writeInPlace(encoded { $0.numberStyle = .precise }, to: file.url)
        try await waitUntil { store.lastError == nil }

        #expect(store.lastError == nil)
        #expect(store.settings.numberStyle == .precise)
    }
}
