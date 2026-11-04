import AppKit
import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// The index holds text typed by hand, so these keep it true to the catalog and the app.
@MainActor
struct SettingsIndexTests {
    private static let catalog: [String: String] = {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../Sources/GlassWorkUI/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any]
        else { return [:] }
        return strings.compactMapValues { entry in
            let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
            let russian = localizations?["ru"] as? [String: Any]
            return (russian?["stringUnit"] as? [String: Any])?["value"] as? String
        }
    }()

    private func titles(_ query: String) -> [String] {
        SettingsIndex.search(query).map(\.result.setting.english)
    }

    @Test func idsAreUnique() {
        let ids = SettingsIndex.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyTitleMatchesTheCatalog() {
        #expect(!Self.catalog.isEmpty)
        for result in SettingsIndex.all {
            #expect(Self.catalog[result.setting.english] == result.setting.russian, "\(result.id)")
        }
    }

    @Test func everyBreadcrumbIsTranslated() {
        for key in Set(SettingsIndex.all.flatMap(\.path)) {
            #expect(Self.catalog[key] != nil, "\(key)")
        }
    }

    @Test func everyModuleCanBeFound() {
        let found = Set(SettingsIndex.all.compactMap(\.module))
        for module in ModuleID.allCases where module.isAvailable {
            #expect(found.contains(module), "\(module)")
        }
    }

    @Test func everyOptionRowCanBeFound() {
        let ids = Set(SettingsIndex.all.map(\.id))
        for spec in ModuleOptionSpec.all {
            #expect(ids.contains(spec.id), "\(spec.id)")
        }
    }

    @Test func optionsAreFoundNotOnlyPages() {
        #expect(titles("swap").contains("Show swap in panel"))
        #expect(titles("Sampling").contains("Sampling interval"))
    }

    @Test func aChoiceFindsItsRow() {
        #expect(titles("Pressure").contains("Show as"))
    }

    @Test func russianWorksInAnEnglishApp() {
        #expect(titles("вент").contains("Fans"))
        #expect(titles("своп").contains("Show swap in panel"))
    }

    @Test func theExamplesFromTheDesignWork() {
        #expect(titles("кривая").first == "Curves")
        #expect(titles("горячие клавиши").first == "Shortcuts")
    }

    @Test func settingsThatCameWithTheWidgetsCanBeFound() {
        #expect(titles("Фоторамка").contains("Photo Frame"))
        #expect(titles("Birthdays").contains("Birthdays"))
    }

    @Test func anOptionOpensItsModule() throws {
        let hit = try #require(SettingsIndex.search("Sampling").first?.result)
        #expect(hit.destination == .module(.cpu))
    }

    @Test func aHubOptionOpensTheMenuBarPage() throws {
        let hit = try #require(SettingsIndex.search("Tile size").first?.result)
        #expect(hit.destination == .menuBar)
    }

    @Test func nothingMatchesNonsense() {
        #expect(SettingsIndex.search("qqqzzz").isEmpty)
    }
}

/// Pixel snapshots depend on the exact macOS and Xcode version, so they run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct SettingsSearchSnapshotTests {
    @Test(arguments: [true, false])
    func english(dark: Bool) {
        let view = SettingsSearchResults(query: "swap", opened: "memory.showSwap") { _ in }
            .frame(width: 240, height: 240)
        snapshotPanel(view, name: "english", dark: dark)
    }

    @Test(arguments: [true, false])
    func russian(dark: Bool) {
        let view = SettingsSearchResults(query: "своп", opened: nil) { _ in }
            .frame(width: 240, height: 240)
        snapshotPanel(view, name: "russian", dark: dark)
    }

    @Test func nothingFound() {
        let view = SettingsSearchResults(query: "qqqzzz", opened: nil) { _ in }
            .frame(width: 240, height: 120)
        snapshotPanel(view, name: "empty")
    }
}
