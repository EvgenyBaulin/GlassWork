import Foundation
@testable import GlassWorkCore
import Testing

/// The sample entries are handmade in the shape the system dictionary returns, with their own wording.
struct WordOfDayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private let date = Date(timeIntervalSince1970: 1_793_750_400 + 12 * 3600)

    private let dictionaryText = """
    gleam | ɡliːm | noun [mass noun] a faint or brief light, often one reflected from something: a gleam of \
    light under the door. ORIGIN Old English glǣm.
    """

    private let thesaurusText = "gleam noun the gleam of a distant lamp. glimmer, flicker, glint, flash; "
        + "informal wink. ANTONYMS darkness. WORD LINKS gleamy: shining"

    @Test func readsADictionaryEntry() {
        let entry = DictionaryEntryParser.parse(dictionaryText, word: "gleam")
        #expect(entry.pronunciation == "ɡliːm")
        #expect(entry.partOfSpeech == "noun")
        #expect(entry.definition == "a faint or brief light, often one reflected from something")
        #expect(entry.synonyms.isEmpty)
    }

    @Test func readsAThesaurusEntry() {
        let entry = DictionaryEntryParser.parse(thesaurusText, word: "gleam")
        #expect(entry.pronunciation == nil)
        #expect(entry.partOfSpeech == "noun")
        #expect(entry.definition == nil)
        #expect(entry.example == "the gleam of a distant lamp.")
        #expect(entry.synonyms == ["glimmer", "flicker", "glint", "flash", "informal wink"])
    }

    @Test func thesaurusEntryWithoutAnExample() {
        let entry = DictionaryEntryParser.parse("gleam adjective glimmering, shining, bright", word: "gleam")
        #expect(entry.example == nil)
        #expect(entry.synonyms == ["glimmering", "shining", "bright"])
    }

    @Test func skipsSenseNumbersAndStopsAtTheLimit() {
        let text = "gleam verb 1 the lamp gleamed. " + (1 ... 20).map { "word\($0)" }.joined(separator: ", ") + ". 2 more."
        let entry = DictionaryEntryParser.parse(text, word: "gleam")
        #expect(entry.partOfSpeech == "verb")
        #expect(entry.synonyms.count == DictionaryEntryParser.maxSynonyms)
        #expect(entry.synonyms.first == "word1")
    }

    @Test func longDefinitionsAreClipped() {
        let long = String(repeating: "shining brightly ", count: 40)
        let entry = DictionaryEntryParser.parse("gleam | ɡliːm | adjective \(long)", word: "gleam")
        let definition = entry.definition ?? ""
        #expect(definition.count <= DictionaryEntryParser.maxDefinition + 1)
        #expect(definition.hasSuffix("…"))
    }

    @Test func unknownTextGivesAnEmptyEntry() {
        #expect(DictionaryEntryParser.parse("", word: "gleam") == DictionaryEntry())
    }

    @Test func theSameDayGivesTheSameWord() {
        let first = WordList.word(on: date, calendar: calendar)
        #expect(first == WordList.word(on: date.addingTimeInterval(3600), calendar: calendar))
        let next = WordList.word(on: date.addingTimeInterval(86400), calendar: calendar)
        #expect(next != first)
    }

    @Test func listHasNoRepeatsAndWraps() {
        #expect(Set(WordList.words).count == WordList.words.count)
        let days = WordList.words.count
        let later = date.addingTimeInterval(Double(days) * 86400)
        #expect(WordList.word(on: later, calendar: calendar) == WordList.word(on: date, calendar: calendar))
    }

    @MainActor
    @Test func providerLooksUpAndCaches() {
        var calls = 0
        let provider = WordOfDayProvider { word in
            calls += 1
            return "\(word) | ɡliːm | noun a faint light: a gleam."
        }
        let words = provider.recent(3, at: date, calendar: calendar)
        #expect(words.count == 3)
        #expect(Set(words.map(\.day)).count == 3)
        #expect(words.first?.definition == "a faint light")
        _ = provider.recent(3, at: date, calendar: calendar)
        #expect(calls == 3)
    }

    @MainActor
    @Test func unknownWordsAreAskedForOncePerHour() {
        var calls = 0
        let provider = WordOfDayProvider { _ in
            calls += 1
            return nil
        }
        for second in 0 ..< 10 {
            _ = provider.word(on: date, now: date.addingTimeInterval(Double(second) * 2), calendar: calendar)
        }
        #expect(calls == 1)
        _ = provider.word(on: date, now: date.addingTimeInterval(3601), calendar: calendar)
        #expect(calls == 2)
    }

    @MainActor
    @Test func unknownWordsKeepTheirName() {
        let provider = WordOfDayProvider { _ in nil }
        let today = provider.word(on: date, calendar: calendar)
        #expect(today.word == WordList.word(on: date, calendar: calendar))
        #expect(today.definition == nil)
    }
}
