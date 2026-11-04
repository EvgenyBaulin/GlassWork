import Foundation

/// When macOS really asked a widget for fresh content, in a small file in the shared container.
///
/// The system decides how often that is, so this is the only way to know. Nothing leaves the Mac.
public struct WidgetRefreshLog: Sendable {
    private static let limit = 256 * 1024

    public let url: URL

    public init(directory: URL = AppGroup.containerURL) {
        url = directory.appending(path: "widget-refresh.log", directoryHint: .notDirectory)
    }

    /// One line: the time, the widget, and how old its data was. Appends, because widgets ask at the same moment.
    public func record(kind: String, dataDate: Date?, at date: Date = Date()) {
        let age = dataDate.map { String(Int(date.timeIntervalSince($0))) } ?? "-"
        let line = Data("\(date.ISO8601Format()) \(kind) \(age)\n".utf8)
        trimIfFull()
        guard let file = try? FileHandle(forWritingTo: url) else {
            try? line.write(to: url)
            return
        }
        defer { try? file.close() }
        _ = try? file.seekToEnd()
        try? file.write(contentsOf: line)
    }

    private func trimIfFull() {
        guard let data = try? Data(contentsOf: url), data.count > Self.limit else { return }
        try? data.suffix(Self.limit / 2).write(to: url, options: .atomic)
    }
}
