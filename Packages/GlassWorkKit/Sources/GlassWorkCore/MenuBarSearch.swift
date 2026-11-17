import Foundation

/// One item another app has put in the menu bar, as the accessibility tree describes it.
public struct MenuBarEntry: Sendable, Equatable, Identifiable {
    public var pid: Int32
    /// Where it is among the app's menu bar items, so it can be found again to press it.
    public var index: Int
    public var appName: String
    /// What the item calls itself. Nil when it says nothing useful.
    public var title: String?
    public var minX: Double
    public var width: Double

    public init(pid: Int32, index: Int, appName: String, title: String?, minX: Double, width: Double) {
        self.pid = pid
        self.index = index
        self.appName = appName
        self.title = title
        self.minX = minX
        self.width = width
    }

    public var id: String {
        "\(pid):\(index)"
    }

    public var midX: Double {
        minX + width / 2
    }

    /// The item's own name, else the app's.
    public var name: String {
        title ?? appName
    }

    /// The first of title, description and help that says something. Apps often leave the title empty, and the
    /// description is then what a screen reader reads.
    public static func label(title: String?, description: String?, help: String?) -> String? {
        for text in [title, description, help] {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}

/// Which part of the menu bar an item is in, judged from where the separators are.
public enum MenuBarSection: Sendable, Equatable {
    case visible, hidden, alwaysHidden
}

/// Finding menu bar items by name. Pure, so the ranking is tested without any other app running.
public enum MenuBarSearch {
    /// Left of a separator is hidden by it. With no separator in the bar nothing is hidden.
    public static func section(
        of entry: MenuBarEntry,
        separatorMaxX: Double?,
        alwaysHiddenMaxX: Double?
    ) -> MenuBarSection {
        if let alwaysHiddenMaxX, entry.midX < alwaysHiddenMaxX {
            return .alwaysHidden
        }
        if let separatorMaxX, entry.midX < separatorMaxX {
            return .hidden
        }
        return .visible
    }

    /// What can be searched: the hidden items, or everything when `showAll` is on. Closest to the clock first.
    public static func candidates(
        _ entries: [MenuBarEntry],
        separatorMaxX: Double?,
        alwaysHiddenMaxX: Double?,
        showAll: Bool
    ) -> [MenuBarEntry] {
        let wanted = showAll ? entries : entries.filter {
            section(of: $0, separatorMaxX: separatorMaxX, alwaysHiddenMaxX: alwaysHiddenMaxX) != .visible
        }
        return wanted.sorted { $0.midX > $1.midX }
    }

    /// Items whose name or app matches, best match first. Case and accents do not matter. An empty query keeps
    /// the order it was given.
    public static func results(_ entries: [MenuBarEntry], query: String) -> [MenuBarEntry] {
        let needle = fold(query)
        guard !needle.isEmpty else { return entries }
        let ranked = entries.enumerated().compactMap { offset, entry in
            rank(entry, needle: needle).map { Ranked(rank: $0, offset: offset, entry: entry) }
        }
        return ranked.sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }.map(\.entry)
    }

    private struct Ranked {
        var rank: Int
        var offset: Int
        var entry: MenuBarEntry
    }

    private static func rank(_ entry: MenuBarEntry, needle: String) -> Int? {
        let name = fold(entry.name)
        if name.hasPrefix(needle) {
            return 0
        }
        if name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(needle) }) {
            return 1
        }
        if name.contains(needle) {
            return 2
        }
        return fold(entry.appName).contains(needle) ? 3 : nil
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
