import Foundation
@testable import GlassWorkCore
import Testing

struct IslandFeedRulesTests {
    private let now = Date(timeIntervalSince1970: 1_794_850_000)

    private func file(_ name: String, downloading: Bool = false, age: TimeInterval = 0) -> DockFile {
        DockFile(
            path: "/Users/someone/Downloads/\(name)", name: DockFiles.displayName(of: name), size: 1,
            added: now.addingTimeInterval(-age), isDownloading: downloading
        )
    }

    @Test func aPartialFileTakesThePathOfItsFinalName() {
        let result = IslandFeedRules.downloads(from: [file("report.pdf.crdownload", downloading: true)])
        #expect(result.map(\.path) == ["/Users/someone/Downloads/report.pdf"])
        #expect(result.first?.name == "report.pdf")
    }

    @Test func aFinishedFileMatchesTheEarlierDownload() {
        let before = IslandFeedRules.downloads(from: [file("a.zip.download", downloading: true)])
        let after = IslandFeedRules.downloads(from: [file("a.zip")])
        #expect(after.map(\.path) == before.map(\.path))
    }

    @Test func aFileAlsoInProgressIsNotListedAsFinished() {
        let result = IslandFeedRules.downloads(from: [
            file("a.zip", age: 5), file("a.zip.part", downloading: true),
        ])
        #expect(result.count == 1)
        #expect(result.first?.isDownloading == true)
    }

    @Test func downloadsComeFirstAndFinishedOnesAreLimited() {
        var files = (0 ..< 30).map { file("f\($0).txt", age: Double($0)) }
        files.append(file("x.bin.opdownload", downloading: true, age: 100))
        let result = IslandFeedRules.downloads(from: files)
        #expect(result.count == 1 + IslandFeedRules.finishedLimit)
        #expect(result.first?.isDownloading == true)
        #expect(result[1].name == "f0.txt")
    }

    @Test func brightnessChangesNeedARealStep() {
        #expect(!IslandFeedRules.brightnessChanged(from: 0.5, to: 0.51))
        #expect(IslandFeedRules.brightnessChanged(from: 0.5, to: 0.5625))
        #expect(!IslandFeedRules.brightnessChanged(from: nil, to: nil))
        #expect(IslandFeedRules.brightnessChanged(from: nil, to: 0.5))
        #expect(IslandFeedRules.brightnessChanged(from: 0.5, to: nil))
    }
}
