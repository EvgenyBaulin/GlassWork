import CoreServices
import Foundation

/// Picks today's word and looks it up in the Mac's own dictionary. Nothing leaves the Mac.
///
/// Only the app calls this: the widget extension is sandboxed and reads the result from the snapshot.
@MainActor
public final class WordOfDayProvider {
    /// A word the dictionary did not know is asked for again after an hour, not on every snapshot,
    /// since snapshots are taken every couple of seconds while desktop widgets are shown.
    private static let retryAfter: TimeInterval = 3600
    private struct CacheEntry {
        let word: WordOfDay
        let askedAt: Date
        let isMissing: Bool
    }

    private var cache: [String: CacheEntry] = [:]
    private let lookup: ((String) -> String?)?
    private var settings = WordOfDaySettings()
    private var dictionary: SystemDictionary?

    /// `lookup` returns the dictionary's text for a word; tests replace it.
    public init(lookup: ((String) -> String?)? = nil) {
        self.lookup = lookup
    }

    /// Takes the user's choice. A new language, dictionary or level means other words, so the cache starts over.
    public func apply(_ new: WordOfDaySettings, installed: [SystemDictionary]) {
        let chosen = installed.first { $0.id == new.dictionaryID && $0.languages.contains(new.language) }
        guard new != settings || chosen != dictionary else { return }
        settings = new
        dictionary = chosen
        cache = [:]
    }

    /// The text the first active dictionary gives for a word, or nil when none knows it.
    public nonisolated static func systemDefinition(for word: String) -> String? {
        SystemDictionaries.definition(for: word, in: nil)
    }

    /// Today's word first, then the days before it.
    public func recent(_ count: Int, at date: Date, calendar: Calendar = .current) -> [WordOfDay] {
        (0 ..< count).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { word(on: $0, now: date, calendar: calendar) }
        }
    }

    /// `now` decides when a word the dictionary did not know is tried again.
    public func word(on date: Date, now: Date? = nil, calendar: Calendar = .current) -> WordOfDay {
        let day = ScreenTimeLog.dayKey(date, calendar: calendar)
        let now = now ?? date
        if let cached = cache[day], !cached.isMissing || now.timeIntervalSince(cached.askedAt) < Self.retryAfter {
            return cached.word
        }
        let word = WordList.word(on: date, language: settings.language, level: settings.level, calendar: calendar)
        let text = lookup.map { $0(word) } ?? SystemDictionaries.definition(for: word, in: dictionary)
        let entry = text.map { raw in
            settings.language == "en"
                ? DictionaryEntryParser.parse(raw, word: word)
                : DictionaryEntryParser.parsePlain(raw, word: word)
        } ?? DictionaryEntry()
        let result = WordOfDay(day: day, word: word, entry: entry)
        cache[day] = CacheEntry(word: result, askedAt: now, isMissing: entry == DictionaryEntry())
        for key in cache.keys.sorted().dropLast(30) {
            cache[key] = nil
        }
        return result
    }
}
