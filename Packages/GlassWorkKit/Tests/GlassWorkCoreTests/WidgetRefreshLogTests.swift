import Foundation
@testable import GlassWorkCore
import Testing

struct WidgetRefreshLogTests {
    private func makeLog() throws -> WidgetRefreshLog {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RefreshLog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return WidgetRefreshLog(directory: folder)
    }

    @Test func eachRefreshIsOneLineWithTheAgeOfTheData() throws {
        let log = try makeLog()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        log.record(kind: "cpu", dataDate: now.addingTimeInterval(-90), at: now)
        log.record(kind: "fans", dataDate: nil, at: now)
        let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" cpu 90"))
        #expect(lines[1].hasSuffix(" fans -"))
    }

    @Test func aFullFileKeepsItsNewestLines() throws {
        let log = try makeLog()
        try Data(repeating: 65, count: 300 * 1024).write(to: log.url)
        log.record(kind: "cpu", dataDate: nil)
        let text = try String(contentsOf: log.url, encoding: .utf8)
        #expect(text.utf8.count < 200 * 1024)
        #expect(text.hasSuffix(" cpu -\n"))
    }
}
