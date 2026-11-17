import CoreServices
import Foundation

/// What Word of the Day uses: the language of its words, the dictionary that gives the meaning, how rare the words are.
/// Old settings files lack these keys, so every key is optional on decoding.
public struct WordOfDaySettings: Codable, Sendable, Equatable {
    public var language = "en"
    /// The bundle identifier of a dictionary, or nil for the first one the Mac has active.
    public var dictionaryID: String?
    public var level = WordLevel.common

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        dictionaryID = try container.decodeIfPresent(String.self, forKey: .dictionaryID)
        level = (try? container.decodeIfPresent(WordLevel.self, forKey: .level)) ?? .common
    }
}

/// A dictionary installed on this Mac.
public struct SystemDictionary: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// The languages its headwords are in, such as `en`, or `ru` and `en` for a Russian–English dictionary.
    public var languages: [String]
    public var url: URL

    public init(id: String, name: String, languages: [String], url: URL) {
        self.id = id
        self.name = name
        self.languages = languages
        self.url = url
    }
}

public enum SystemDictionaries {
    /// Where macOS keeps dictionaries: downloaded ones live in an asset folder, the rest in the Library folders.
    public static var searchFolders: [URL] {
        [
            URL(filePath: "/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS"),
            URL(filePath: "/Library/Dictionaries"),
            URL(filePath: NSHomeDirectory()).appending(path: "Library/Dictionaries"),
        ]
    }

    /// Reads each dictionary's own Info.plist. A folder that cannot be read counts as empty.
    public static func installed(in folders: [URL] = searchFolders) -> [SystemDictionary] {
        var found: [SystemDictionary] = []
        for folder in folders {
            guard let walker = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                if url.pathExtension == "dictionary" {
                    walker.skipDescendants()
                    if let dictionary = read(url) {
                        found.append(dictionary)
                    }
                } else if walker.level > 4 {
                    walker.skipDescendants()
                }
            }
        }
        var seen = Set<String>()
        return found.filter { seen.insert($0.id).inserted }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func read(_ url: URL) -> SystemDictionary? {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let id = info["CFBundleIdentifier"] as? String ?? url.lastPathComponent
        let name = info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let entries = info["DCSDictionaryLanguages"] as? [[String: Any]] ?? []
        var languages = entries.compactMap { $0["DCSDictionaryIndexLanguage"] as? String }
        if languages.isEmpty, let primary = info["DCSDictionaryPrimaryLanguage"] as? String {
            languages = [primary]
        }
        var unique: [String] = []
        for language in languages where !unique.contains(language) {
            unique.append(language)
        }
        return SystemDictionary(id: id, name: name, languages: unique, url: url)
    }

    /// Languages that have both a word list and a dictionary. English is always offered, since the Mac's own
    /// dictionary covers it even when the folders above could not be read.
    public static func languages(in dictionaries: [SystemDictionary]) -> [String] {
        WordList.languages.filter { language in
            language == "en" || dictionaries.contains { $0.languages.contains(language) }
        }
    }

    /// The dictionaries that know the words of a language.
    public static func dictionaries(for language: String, in dictionaries: [SystemDictionary]) -> [SystemDictionary] {
        dictionaries.filter { $0.languages.contains(language) }
    }

    private typealias Create = @convention(c) (CFURL) -> Unmanaged<CFTypeRef>?

    /// Dictionaries opened so far, by identifier: each one is created once and kept.
    private final class Opened: @unchecked Sendable {
        // Safe because every access to `byID` holds `lock`.
        private let lock = NSLock()
        private var byID: [String: DCSDictionary] = [:]

        func dictionary(for id: String, create: () -> DCSDictionary?) -> DCSDictionary? {
            lock.lock()
            defer { lock.unlock() }
            if let known = byID[id] {
                return known
            }
            guard let made = create() else { return nil }
            byID[id] = made
            return made
        }
    }

    private static let opened = Opened()

    /// The text one dictionary gives for a word. With no dictionary chosen the first active one answers. A chosen
    /// dictionary that cannot be opened gives nothing: another dictionary's text would be the wrong meaning.
    ///
    /// Opening a dictionary by its folder has no public call, so this uses the one DictionaryServices has inside.
    /// It follows the Create rule, so the handle is owned here and kept for the next lookup.
    public static func definition(for word: String, in dictionary: SystemDictionary?) -> String? {
        let range = CFRangeMake(0, (word as NSString).length)
        guard let dictionary else {
            return DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String?
        }
        guard let ref = opened.dictionary(for: dictionary.id, create: { create(at: dictionary.url) }) else {
            return nil
        }
        return DCSCopyTextDefinition(ref, word as CFString, range)?.takeRetainedValue() as String?
    }

    private static func create(at url: URL) -> DCSDictionary? {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "DCSDictionaryCreate"),
              let created = unsafeBitCast(symbol, to: Create.self)(url as CFURL)
        else { return nil }
        return unsafeBitCast(created.takeRetainedValue(), to: DCSDictionary.self)
    }
}
