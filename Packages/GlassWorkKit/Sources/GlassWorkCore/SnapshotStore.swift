import Foundation

/// Stores small Codable values as JSON files in a directory.
///
/// The app writes snapshots of collected data here; the widget extension only reads them.
public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL = AppGroup.containerURL.appending(path: "Snapshots", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    public func write(_ value: some Encodable, for key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url(for: key), options: .atomic)
    }

    public func read<Value: Decodable>(_: Value.Type, for key: String) -> Value? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    /// Raw bytes such as images, which JSON would make a third larger.
    public func writeData(_ data: Data, for key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: dataURL(for: key), options: .atomic)
    }

    public func readData(for key: String) -> Data? {
        try? Data(contentsOf: dataURL(for: key))
    }

    public func removeData(for key: String) {
        try? FileManager.default.removeItem(at: dataURL(for: key))
    }

    private func dataURL(for key: String) -> URL {
        directory.appending(path: "\(key).data", directoryHint: .notDirectory)
    }

    private func url(for key: String) -> URL {
        directory.appending(path: "\(key).json", directoryHint: .notDirectory)
    }
}
