import Foundation
@testable import GlassWorkCore
import Testing

struct CrashReportParserTests {
    @Test func readsTheAppsOwnFrameUnderTheStandardLibrary() throws {
        let crash = try #require(CrashReportParser.summary(of: fixture("crash-report-app.ips")))
        #expect(crash.process == "GlassWork")
        #expect(crash.build == "34")
        #expect(crash.exception == "EXC_BREAKPOINT")
        #expect(crash.function == "AppUsageGrouping.usage")
        #expect(crash.file == "AppUsage.swift")
        #expect(crash.line == 217)
        #expect(crash.date == Date(timeIntervalSince1970: 1_794_761_992))
    }

    @Test func aReportWithoutSymbolsStillGivesTheException() throws {
        let crash = try #require(CrashReportParser.summary(of: fixture("crash-report-no-symbols.ips")))
        #expect(crash.process == "GlassWorkWidgets")
        #expect(crash.exception == "EXC_BAD_ACCESS")
        #expect(crash.function == nil)
        #expect(crash.file == nil)
    }

    @Test func somethingElseIsNil() {
        #expect(CrashReportParser.summary(of: Data("not a report".utf8)) == nil)
        #expect(CrashReportParser.summary(of: Data("{}\n[]".utf8)) == nil)
    }

    @Test(arguments: [
        ("specialized static AppUsageGrouping.usage(apps:counters:)", "AppUsageGrouping.usage"),
        ("closure #1 in AppUsageStore.read(at:)", "AppUsageStore.read"),
        ("specialized Dictionary.init<A>(uniqueKeysWithValues:)", "Dictionary.init"),
        ("main", "main"),
    ])
    func shortensSymbols(symbol: String, expected: String) {
        #expect(CrashReportParser.function(symbol) == expected)
    }

    @Test func theLogLineHasNoPathsOrFreeText() {
        let crash = CrashSummary(
            process: "GlassWork",
            build: "34",
            exception: "EXC_BREAKPOINT",
            function: "AppUsageGrouping.usage",
            file: "AppUsage.swift",
            line: 217,
            date: Date(timeIntervalSince1970: 1_794_761_992)
        )
        #expect(DiagnosticEvent.crashed(crash).line
            == "crash: GlassWork build 34, EXC_BREAKPOINT in AppUsageGrouping.usage AppUsage.swift:217, "
            + "crashed at 2026-11-15T16:59:52Z")
        let hostile = CrashSummary(process: "/Users/someone/x", build: "1", exception: "a b")
        #expect(DiagnosticEvent.crashed(hostile).line == "crash: Userssomeonex build 1, ab")
    }
}

struct CrashReportFolderTests {
    private func write(_ name: String, in folder: URL, at date: Date) throws {
        let url = folder.appending(path: name)
        try Data("x".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
    }

    @Test func findsOnlyNewReportsOfGlassWorkOldestFirst() throws {
        let folder = temporaryFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try write("GlassWork-2026-11-15-200019.ips", in: folder, at: start.addingTimeInterval(20))
        try write("GlassWorkWidgets-2026-11-15-200001.ips", in: folder, at: start.addingTimeInterval(10))
        try write("GlassWork-2026-11-14-100000.ips", in: folder, at: start.addingTimeInterval(-10))
        try write("Safari-2026-11-15-200019.ips", in: folder, at: start.addingTimeInterval(30))
        try write("GlassWorkHelper-2026-11-15-200019.ips", in: folder, at: start.addingTimeInterval(30))
        try write("GlassWork-2026-11-15-200019.diag", in: folder, at: start.addingTimeInterval(30))

        let names = CrashReportFolder.reports(in: folder, after: start).map(\.url.lastPathComponent)

        #expect(names == ["GlassWorkWidgets-2026-11-15-200001.ips", "GlassWork-2026-11-15-200019.ips"])
    }

    @Test func aMissingFolderHasNoReports() {
        #expect(CrashReportFolder.reports(in: temporaryFolder(), after: .distantPast).isEmpty)
    }
}
