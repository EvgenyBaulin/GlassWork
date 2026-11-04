import CoreServices
import Foundation

/// Picks today's word and looks it up in the Mac's own dictionary. Nothing leaves the Mac.
///
/// Only the app calls this: the widget extension is sandboxed and reads the result from the snapshot.
@MainActor
public final class WordOfDayProvider {
    private var cache: [String: WordOfDay] = [:]
    private let lookup: (String) -> String?

    /// `lookup` returns the dictionary's text for a word; tests replace it.
    public init(lookup: @escaping (String) -> String? = WordOfDayProvider.systemDefinition) {
        self.lookup = lookup
    }

    /// The text the first active dictionary gives for a word, or nil when none knows it.
    public nonisolated static func systemDefinition(for word: String) -> String? {
        let range = CFRangeMake(0, (word as NSString).length)
        return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
    }

    /// Today's word first, then the days before it.
    public func recent(_ count: Int, at date: Date, calendar: Calendar = .current) -> [WordOfDay] {
        (0 ..< count).compactMap { back in
            calendar.date(byAdding: .day, value: -back, to: date).map { word(on: $0, calendar: calendar) }
        }
    }

    public func word(on date: Date, calendar: Calendar = .current) -> WordOfDay {
        let day = ScreenTimeLog.dayKey(date, calendar: calendar)
        if let cached = cache[day] {
            return cached
        }
        let word = WordList.word(on: date, calendar: calendar)
        let entry = lookup(word).map { DictionaryEntryParser.parse($0, word: word) } ?? DictionaryEntry()
        let result = WordOfDay(day: day, word: word, entry: entry)
        // A word the dictionary does not know yet may be known later, so only real answers are kept.
        if entry != DictionaryEntry() {
            cache[day] = result
        }
        for key in cache.keys.sorted().dropLast(30) {
            cache[key] = nil
        }
        return result
    }
}
