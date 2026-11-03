import Foundation

/// The last few versions of settings.json, taken before anything replaces it.
public struct SettingsBackups: Sendable {
    public struct Backup: Identifiable, Sendable, Equatable {
        public var id: URL {
            url
        }

        public let url: URL
        public let date: Date
    }

    public static let limit = 10
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func list() -> [Backup] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return date.map { Backup(url: url, date: $0) }
        }
        .sorted { $0.date > $1.date }
    }

    @discardableResult
    public func create(from settings: AppSettings, at date: Date = Date()) -> URL? {
        let stamp = date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
        let url = directory.appending(path: "settings-\(stamp.replacing(":", with: "-")).json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try SettingsFile(url: url).save(settings)
            prune()
            return url
        } catch {
            return nil
        }
    }

    public func load(_ backup: Backup) -> AppSettings? {
        try? SettingsFile(url: backup.url).load()
    }

    private func prune() {
        for backup in list().dropFirst(Self.limit) {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }
}
