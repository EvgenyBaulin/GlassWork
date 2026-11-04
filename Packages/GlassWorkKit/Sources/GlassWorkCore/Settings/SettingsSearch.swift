import Foundation

/// A setting as search sees it. Both languages count, whatever the app's language is.
public struct SearchableSetting: Sendable, Equatable, Identifiable {
    public let id: String
    public let english: String
    public let russian: String
    /// Other words people use for it, in either language.
    public let keywords: [String]

    public init(id: String, english: String, russian: String, keywords: [String] = []) {
        self.id = id
        self.english = english
        self.russian = russian
        self.keywords = keywords
    }
}

public struct SettingMatch: Sendable, Equatable {
    public let setting: SearchableSetting
    /// The word that matched, for a hit the visible title does not explain.
    public let matchedWord: String?
}

public enum SettingsSearch {
    public static let limit = 30

    /// Best first: a title that starts with the query, then a word in a title, then keywords.
    public static func matches(_ query: String, in settings: [SearchableSetting]) -> [SettingMatch] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        // Sorting by the original place too keeps the list in the same order from one key press to the next.
        let ranked = settings.enumerated().compactMap { index, setting in
            rank(of: setting, for: needle).map { found in
                Ranked(
                    rank: found.rank,
                    index: index,
                    match: SettingMatch(setting: setting, matchedWord: found.word)
                )
            }
        }
        return ranked
            .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }
            .prefix(limit)
            .map(\.match)
    }

    private struct Ranked {
        let rank: Int
        let index: Int
        let match: SettingMatch
    }

    /// `ё` and `е` are one letter here, as they are for most people typing.
    public static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func rank(of setting: SearchableSetting, for needle: String) -> (rank: Int, word: String?)? {
        let titles = [setting.english, setting.russian]
        for (rank, test) in [isPrefix, isWordPrefix, isInside].enumerated() {
            if let title = titles.first(where: { test(normalized($0), needle) }) {
                return (rank, title == setting.english ? nil : title)
            }
        }
        for (rank, test) in [isPrefix, isInside].enumerated() {
            if let word = setting.keywords.first(where: { test(normalized($0), needle) }) {
                return (rank + 3, word)
            }
        }
        return nil
    }

    private static func isPrefix(_ text: String, _ needle: String) -> Bool {
        text.hasPrefix(needle)
    }

    private static func isWordPrefix(_ text: String, _ needle: String) -> Bool {
        text.split { !$0.isLetter && !$0.isNumber }.contains { $0.hasPrefix(needle) }
    }

    private static func isInside(_ text: String, _ needle: String) -> Bool {
        text.contains(needle)
    }
}
