import Foundation

/// A word and what the system dictionary says about it.
public struct WordOfDay: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        day
    }

    /// The day it belongs to, as `yyyy-MM-dd`.
    public var day: String
    public var word: String
    public var pronunciation: String?
    public var partOfSpeech: String?
    public var definition: String?
    /// Filled when the first match was a thesaurus entry, which lists related words and no meaning.
    public var synonyms: [String] = []

    public init(day: String, word: String, entry: DictionaryEntry = DictionaryEntry()) {
        self.day = day
        self.word = word
        pronunciation = entry.pronunciation
        partOfSpeech = entry.partOfSpeech
        definition = entry.definition
        synonyms = entry.synonyms
    }
}

public struct DictionaryEntry: Sendable, Equatable {
    public var pronunciation: String?
    public var partOfSpeech: String?
    public var definition: String?
    public var synonyms: [String] = []

    public init(
        pronunciation: String? = nil,
        partOfSpeech: String? = nil,
        definition: String? = nil,
        synonyms: [String] = []
    ) {
        self.pronunciation = pronunciation
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.synonyms = synonyms
    }
}

/// Reads the plain text that the system dictionary returns for a word. The first dictionary with the word
/// answers, so this is either a dictionary entry (`word | pronunciation | noun meaning: example. ORIGIN ...`)
/// or a thesaurus entry (`word noun example. synonym, synonym ANTONYMS ...`).
public enum DictionaryEntryParser {
    private static let partsOfSpeech: Set<String> = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition", "conjunction", "interjection",
        "exclamation", "determiner", "abbreviation", "prefix", "suffix", "modal", "numeral",
    ]
    /// Where the useful part of an entry stops.
    private static let sectionMarkers = [
        " ORIGIN", " DERIVATIVES", " PHRASES", " PHRASAL", " USAGE", " ANTONYMS", " WORD LINKS",
        " CHOOSE THE RIGHT WORD",
    ]
    static let maxDefinition = 240
    static let maxSynonyms = 8

    public static func parse(_ raw: String, word: String) -> DictionaryEntry {
        var text = raw.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix(word.lowercased()) {
            text = String(text.dropFirst(word.count)).trimmingCharacters(in: .whitespaces)
        }
        var entry = DictionaryEntry()
        if text.hasPrefix("|"), let close = text.dropFirst().firstIndex(of: "|") {
            let pronunciation = text[text.index(after: text.startIndex) ..< close].trimmingCharacters(in: .whitespaces)
            entry.pronunciation = pronunciation.isEmpty ? nil : pronunciation
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            entry.partOfSpeech = takePartOfSpeech(&text)
            entry.definition = definition(from: text)
            return entry
        }
        entry.partOfSpeech = takePartOfSpeech(&text)
        entry.synonyms = synonyms(from: text)
        return entry
    }

    /// Removes and returns a leading part of speech such as "noun", with its qualifiers like "[mass noun]".
    private static func takePartOfSpeech(_ text: inout String) -> String? {
        guard let first = text.split(separator: " ").first.map({ String($0).lowercased() }),
              partsOfSpeech.contains(first)
        else { return nil }
        text = String(text.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
        return first
    }

    private static func cut(_ text: String) -> String {
        var end = text.endIndex
        for marker in sectionMarkers {
            if let range = text.range(of: marker), range.lowerBound < end {
                end = range.lowerBound
            }
        }
        return String(text[..<end])
    }

    /// Drops "[mass noun]", "(informal)" and a leading sense number.
    private static func stripQualifiers(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        var changed = true
        while changed {
            changed = false
            for pair in [("[", "]"), ("(", ")")] where result.hasPrefix(pair.0) {
                if let close = result.firstIndex(of: Character(pair.1)) {
                    result = String(result[result.index(after: close)...]).trimmingCharacters(in: .whitespaces)
                    changed = true
                }
            }
            if let number = result.split(separator: " ").first, Int(number) != nil {
                result = String(result.dropFirst(number.count)).trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }
        return result
    }

    private static func definition(from text: String) -> String? {
        var body = stripQualifiers(cut(text))
        // The meaning ends where its example sentence begins.
        if let colon = body.range(of: ": ") {
            body = String(body[..<colon.lowerBound])
        }
        body = body.trimmingCharacters(in: CharacterSet(charactersIn: " :;"))
        guard !body.isEmpty else { return nil }
        if body.count > maxDefinition {
            let clipped = body.prefix(maxDefinition)
            let atWord = clipped.lastIndex(of: " ").map { String(clipped[..<$0]) } ?? String(clipped)
            return atWord + "…"
        }
        return body
    }

    private static func synonyms(from text: String) -> [String] {
        var body = stripQualifiers(cut(text))
        // A thesaurus entry gives an example sentence first, then the related words.
        if let stop = body.range(of: ". ") {
            body = String(body[stop.upperBound...])
        } else {
            return []
        }
        let words = body.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .")) }
            .filter { !$0.isEmpty && $0.count < 40 }
        return Array(words.prefix(maxSynonyms))
    }
}
