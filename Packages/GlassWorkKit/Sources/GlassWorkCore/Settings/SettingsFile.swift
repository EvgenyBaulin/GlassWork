import Foundation

/// Reads and writes settings.json, keeping keys this version does not know about.
public struct SettingsFile: Sendable {
    public let url: URL

    public init(url: URL = SettingsFile.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "GlassWork/settings.json", directoryHint: .notDirectory)
    }

    public func load() throws -> AppSettings? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
    }

    public func save(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(settings)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        let merged = Self.overlay(object, on: existingObject())
        let data = try JSONSerialization.data(
            withJSONObject: merged,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func existingObject() -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Recursively applies `new` over `old`; keys only present in `old` survive.
    static func overlay(_ new: [String: Any], on old: [String: Any]) -> [String: Any] {
        var result = old
        for (key, value) in new {
            if let inner = value as? [String: Any], let existing = old[key] as? [String: Any] {
                result[key] = overlay(inner, on: existing)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
