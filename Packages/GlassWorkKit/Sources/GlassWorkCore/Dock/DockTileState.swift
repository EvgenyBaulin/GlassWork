import Foundation

/// What a Dock tile shows besides its icon and running dot.
public struct DockTileState: Equatable, Sendable {
    /// The badge text, such as "3" or "99+". Nil when there is none.
    public var badge: String?
    /// The app asked for attention and has not been looked at.
    public var needsAttention: Bool
    /// The app is running with its windows hidden: the icon is dimmed.
    public var isHidden: Bool

    public init(badge: String? = nil, needsAttention: Bool = false, isHidden: Bool = false) {
        self.badge = badge
        self.needsAttention = needsAttention
        self.isHidden = isHidden
    }
}

/// Badges as the system Dock shows them, and what the tiles of GlassWork's Dock make of them.
public enum DockBadges {
    /// One entry of the system Dock's list of apps: the app's URL and its badge label.
    public struct Item: Equatable, Sendable {
        public var url: String?
        public var label: String?

        public init(url: String?, label: String?) {
            self.url = url
            self.label = label
        }
    }

    /// The most a badge shows. More reads "99+", as in the system Dock.
    public static let cap = 99

    /// Badge labels by app path. Entries with no label, an empty one or "0" are left out.
    public static func labels(from items: [Item]) -> [String: String] {
        var result: [String: String] = [:]
        for item in items {
            guard let path = item.url.flatMap(path(fromURL:)),
                  let label = item.label?.trimmingCharacters(in: .whitespaces),
                  !label.isEmpty, label != "0"
            else { continue }
            result[path] = label
        }
        return result
    }

    /// "file:///Applications/Mail.app/" is "/Applications/Mail.app", as a Dock app stores it.
    public static func path(fromURL text: String) -> String? {
        guard let url = URL(string: text), url.isFileURL else { return nil }
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// The number a label stands for. "12" is 12 and "99+" is 99. A word or a dot is one thing to look at.
    public static func count(of label: String) -> Int {
        let digits = label.trimmingCharacters(in: CharacterSet(charactersIn: "+ ").union(.whitespaces))
        if let number = Int(digits) {
            return max(number, 0)
        }
        return label.isEmpty ? 0 : 1
    }

    /// A count as a badge reads: "7", or "99+" past the cap. Nil for none.
    public static func text(forCount count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > cap ? "\(cap)+" : String(count)
    }

    /// The badge of one app. A number is capped, any other label stays as it is.
    public static func display(_ label: String?) -> String? {
        guard let label, !label.isEmpty, label != "0" else { return nil }
        if Int(label.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) != nil {
            return text(forCount: count(of: label))
        }
        return label
    }

    /// The badge of a folder: the numbers of its apps added. Apps that only say something in words, with no number,
    /// show a dot when there is nothing to add.
    public static func total(of labels: [String]) -> String? {
        var sum = 0
        var hasWord = false
        for label in labels where !label.isEmpty && label != "0" {
            if Int(label.trimmingCharacters(in: CharacterSet(charactersIn: "+"))) != nil {
                sum += count(of: label)
            } else {
                hasWord = true
            }
        }
        if sum > 0 {
            return text(forCount: sum)
        }
        return hasWord ? "•" : nil
    }
}

/// Builds the state of each kind of tile from what has been read.
public enum DockTileStates {
    public static func state(
        for app: DockApp,
        badges: [String: String],
        attention: Set<String>,
        hidden: Set<String>
    ) -> DockTileState {
        DockTileState(
            badge: DockBadges.display(badges[app.path]),
            needsAttention: attention.contains(app.path),
            isHidden: hidden.contains(app.path)
        )
    }

    /// A folder adds up its apps' badges and asks for attention if any of them does. It is never dimmed: it is not
    /// an app that can hide.
    public static func state(for folder: AppFolder, badges: [String: String], attention: Set<String>) -> DockTileState {
        DockTileState(
            badge: DockBadges.total(of: folder.apps.compactMap { badges[$0.path] }),
            needsAttention: folder.apps.contains { attention.contains($0.path) }
        )
    }
}

/// Which apps want attention. The system keeps a bouncing request to itself and publishes no signal for it, so this
/// takes the next best one: an app that is not in front and whose badge has gone up since it was last read.
public struct DockAttention: Sendable, Equatable {
    private var counts: [String: Int] = [:]
    private var isPrimed = false
    public private(set) var asking: Set<String> = []

    public init() {}

    /// - Parameters:
    ///   - labels: Badge labels by app path, as read now.
    ///   - front: The path of the app in front, if it is a Dock app.
    public mutating func update(labels: [String: String], front: String?) {
        var next: [String: Int] = [:]
        for (path, label) in labels {
            next[path] = DockBadges.count(of: label)
        }
        var still: Set<String> = []
        // The first reading is what was already waiting before GlassWork looked: no request.
        if isPrimed {
            for (path, count) in next where path != front {
                if count > (counts[path] ?? 0) || asking.contains(path) {
                    still.insert(path)
                }
            }
        }
        isPrimed = true
        counts = next
        asking = still
    }
}
