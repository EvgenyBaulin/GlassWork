import Foundation

public enum ClipboardKind: String, Codable, Sendable, CaseIterable {
    case text, link, image, file, color
}

public struct ClipboardSettings: Codable, Sendable, Equatable {
    /// Bundle identifiers of password managers. Nothing copied while one of them is in front is kept.
    public static let defaultExcludedApps = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass", "com.markmcguill.strongbox.mac", "in.sinew.Enpass-Desktop",
        "me.proton.pass.electron", "org.keepassxc.keepassxc",
    ]

    /// Off until the user starts it: reading the pasteboard makes macOS show an access alert.
    public var isRecording = false
    /// Off by default: pasting into another app needs Accessibility.
    public var pasteOnClick = false
    public var retentionDays = 30
    public var excludedApps = ClipboardSettings.defaultExcludedApps
    /// The menu bar shows the last item instead of the count. Off, so it stays private on shared screens.
    public var showsLastItem = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case isRecording, pasteOnClick, retentionDays, excludedApps, showsLastItem
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRecording = try container.decodeIfPresent(Bool.self, forKey: .isRecording) ?? false
        pasteOnClick = try container.decodeIfPresent(Bool.self, forKey: .pasteOnClick) ?? false
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 30
        excludedApps = try container.decodeIfPresent([String].self, forKey: .excludedApps)
            ?? Self.defaultExcludedApps
        showsLastItem = try container.decodeIfPresent(Bool.self, forKey: .showsLastItem) ?? false
    }
}

public struct ClipboardEntry: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var kind: ClipboardKind
    /// Text, link or hex color. For files, the paths on separate lines. Empty for images.
    public var text: String
    /// Name of the image in the history folder.
    public var imageName: String?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var byteCount: Int
    public var appName: String?
    public var date: Date
    public var isPinned = false
    /// Equal content has an equal fingerprint, so copying something twice keeps one entry.
    public var fingerprint: String

    public init(
        kind: ClipboardKind,
        text: String,
        byteCount: Int,
        appName: String?,
        date: Date,
        fingerprint: String
    ) {
        self.kind = kind
        self.text = text
        self.byteCount = byteCount
        self.appName = appName
        self.date = date
        self.fingerprint = fingerprint
    }

    public var paths: [String] {
        kind == .file ? text.components(separatedBy: "\n") : []
    }

    /// One line for lists: the text itself, or the file's name.
    public var title: String {
        switch kind {
        case .file:
            let name = paths.first.map { ($0 as NSString).lastPathComponent } ?? ""
            return paths.count > 1 ? "\(name) +\(paths.count - 1)" : name
        case .image:
            return "\(pixelWidth ?? 0) × \(pixelHeight ?? 0)"
        default:
            return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || text.localizedStandardContains(query) || appName?.localizedStandardContains(query) == true
    }
}

/// The history itself: newest first, no repeats, and the storage limits.
public struct ClipboardHistory: Codable, Sendable, Equatable {
    public static let entryLimit = 500

    public private(set) var entries: [ClipboardEntry] = []

    public init(entries: [ClipboardEntry] = []) {
        self.entries = entries
    }

    public var pinned: [ClipboardEntry] {
        entries.filter(\.isPinned)
    }

    public var recent: [ClipboardEntry] {
        entries.filter { !$0.isPinned }
    }

    /// Copying something already in the history moves it to the top and keeps its pin.
    /// Returns the repeat it replaced, whose image is no longer needed.
    @discardableResult
    public mutating func insert(_ entry: ClipboardEntry) -> ClipboardEntry? {
        var new = entry
        let old = entries.first { $0.fingerprint == entry.fingerprint }
        new.isPinned = old?.isPinned ?? false
        entries.removeAll { $0.fingerprint == entry.fingerprint }
        entries.insert(new, at: 0)
        return old
    }

    /// Drops what is past its limits and returns it. Pinned entries are never dropped.
    @discardableResult
    public mutating func prune(at date: Date, retentionDays: Int, limit: Int = entryLimit) -> [ClipboardEntry] {
        let oldest = date.addingTimeInterval(-Double(retentionDays) * 86400)
        let room = max(limit - pinned.count, 0)
        var kept = 0
        var removed: [ClipboardEntry] = []
        entries.removeAll { entry in
            guard !entry.isPinned else { return false }
            kept += 1
            guard entry.date < oldest || kept > room else { return false }
            removed.append(entry)
            return true
        }
        return removed
    }

    public mutating func togglePin(_ id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
    }

    @discardableResult
    public mutating func remove(_ id: ClipboardEntry.ID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Clears everything except what the user chose to keep.
    @discardableResult
    public mutating func removeUnpinned() -> [ClipboardEntry] {
        let removed = recent
        entries = pinned
        return removed
    }

    public func matching(_ query: String, kind: ClipboardKind?) -> [ClipboardEntry] {
        entries.filter { (kind == nil || $0.kind == kind) && $0.matches(query) }
    }
}
