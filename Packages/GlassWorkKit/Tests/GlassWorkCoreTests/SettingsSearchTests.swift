import Foundation
@testable import GlassWorkCore
import Testing

struct SettingsSearchTests {
    private let settings = [
        SearchableSetting(id: "other", english: "Colour of the fan icon", russian: "Цвет значка"),
        SearchableSetting(id: "fans", english: "Fans", russian: "Вентиляторы", keywords: ["обороты", "cooling"]),
        SearchableSetting(id: "curve", english: "Curves", russian: "Кривые", keywords: ["кривая вентилятора"]),
        SearchableSetting(id: "swap", english: "Show swap", russian: "Показывать своп"),
        SearchableSetting(id: "clock", english: "Sky Clock", russian: "Часы неба", keywords: ["Ёлка"]),
    ]

    private func ids(_ query: String) -> [String] {
        SettingsSearch.matches(query, in: settings).map(\.setting.id)
    }

    @Test func anEmptyQueryFindsNothing() {
        #expect(ids("").isEmpty)
        #expect(ids("   ").isEmpty)
    }

    @Test func caseDoesNotMatter() {
        #expect(ids("FANS") == ["fans"])
    }

    @Test func russianFindsTheSettingWhateverTheAppLanguage() {
        #expect(ids("вент").first == "fans")
    }

    @Test func aTitleOutranksAWordInsideAnother() {
        #expect(ids("fan") == ["fans", "other"])
    }

    @Test func aTitleOutranksAKeyword() {
        #expect(ids("вент") == ["fans", "curve"])
    }

    @Test func keywordsAreSearched() {
        #expect(ids("cooling") == ["fans"])
        #expect(ids("обороты") == ["fans"])
    }

    @Test func aWordInTheMiddleOfATitleCounts() {
        #expect(ids("swap") == ["swap"])
        #expect(ids("clock") == ["clock"])
    }

    @Test func yoAndYeAreTheSameLetter() {
        #expect(ids("елка") == ["clock"])
    }

    @Test func spacesAroundTheQueryAreIgnored() {
        #expect(ids("  fans ") == ["fans"])
    }

    @Test func aHitTheTitleExplainsNamesNoWord() throws {
        let match = try #require(SettingsSearch.matches("fans", in: settings).first)
        #expect(match.matchedWord == nil)
    }

    @Test func aHitInTheOtherLanguageSaysWhichWord() throws {
        let match = try #require(SettingsSearch.matches("вент", in: settings).first)
        #expect(match.matchedWord == "Вентиляторы")
    }

    @Test func aHitInAKeywordSaysWhichWord() throws {
        let match = try #require(SettingsSearch.matches("cooling", in: settings).first)
        #expect(match.matchedWord == "cooling")
    }

    @Test func theListHasALimit() {
        let many = (0 ..< 100).map { SearchableSetting(id: "\($0)", english: "Item \($0)", russian: "") }
        #expect(SettingsSearch.matches("item", in: many).count == SettingsSearch.limit)
    }
}
