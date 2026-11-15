import Foundation

/// The few facts of a macOS crash report (`.ips`) that the diagnostic log keeps. Paths, user names, the machine
/// and the other threads stay in the report.
public struct CrashSummary: Sendable, Equatable {
    public var process: String
    public var build: String
    /// Such as `EXC_BREAKPOINT` or `EXC_BAD_ACCESS`.
    public var exception: String
    /// The function of the app where it stopped, such as `AppUsageGrouping.usage`.
    public var function: String?
    public var file: String?
    public var line: Int?
    public var date: Date?

    public init(
        process: String,
        build: String,
        exception: String,
        function: String? = nil,
        file: String? = nil,
        line: Int? = nil,
        date: Date? = nil
    ) {
        self.process = process
        self.build = build
        self.exception = exception
        self.function = function
        self.file = file
        self.line = line
        self.date = date
    }
}

public enum CrashReportParser {
    /// A report is one line of JSON about the app, then one JSON document about the crash.
    public static func summary(of data: Data) -> CrashSummary? {
        guard let newline = data.firstIndex(of: UInt8(ascii: "\n")),
              let header = object(data[..<newline]),
              let body = object(data[data.index(after: newline)...])
        else { return nil }
        let process = header["app_name"] as? String ?? header["name"] as? String ?? body["procName"] as? String
        guard let process else { return nil }
        let exception = body["exception"] as? [String: Any]
        let place = topFrame(body, process: process)
        return CrashSummary(
            process: process,
            build: header["build_version"] as? String ?? "",
            exception: exception?["type"] as? String ?? "",
            function: place?.function,
            file: place?.file,
            line: place?.line,
            date: (body["captureTime"] as? String).flatMap(date) ?? (header["timestamp"] as? String).flatMap(date)
        )
    }

    /// The first frame of the crashed thread that is the app's own code, preferring one with a source line:
    /// frames above it are usually the standard library trapping on the app's behalf.
    private struct Place {
        var function: String
        var file: String?
        var line: Int?
    }

    private static func topFrame(_ body: [String: Any], process: String) -> Place? {
        guard let threads = body["threads"] as? [[String: Any]],
              let index = body["faultingThread"] as? Int, threads.indices.contains(index),
              let frames = threads[index]["frames"] as? [[String: Any]],
              let images = body["usedImages"] as? [[String: Any]]
        else { return nil }
        let own = frames.filter { frame in
            guard let image = frame["imageIndex"] as? Int, images.indices.contains(image) else { return false }
            return images[image]["name"] as? String == process && frame["symbol"] is String
        }
        guard let frame = own.first(where: { $0["sourceLine"] is Int }) ?? own.first,
              let symbol = frame["symbol"] as? String
        else { return nil }
        let file = (frame["sourceFile"] as? String).map { ($0 as NSString).lastPathComponent }
        return Place(function: function(symbol), file: file, line: frame["sourceLine"] as? Int)
    }

    /// `specialized static Foo.bar(a:b:)` and `closure #1 in Foo.bar(a:)` both become `Foo.bar`.
    static func function(_ symbol: String) -> String {
        var name = Substring(symbol)
        if let range = name.range(of: " in ", options: .backwards) {
            name = name[range.upperBound...]
        }
        for prefix in ["specialized ", "static ", "merged "] where name.hasPrefix(prefix) {
            name = name.dropFirst(prefix.count)
        }
        if let open = name.firstIndex(of: "(") {
            name = name[..<open]
        }
        return String(name.replacing(/<[^>]*>/, with: ""))
    }

    private static func object(_ data: Data.SubSequence) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(data))) as? [String: Any]
    }

    /// `2026-11-15 19:59:52.1032 +0300`; the fraction varies in length and is dropped.
    private static func date(_ text: String) -> Date? {
        let parts = text.split(separator: " ")
        guard parts.count == 3 else { return nil }
        let seconds = parts[1].split(separator: ".").first ?? parts[1]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: "\(parts[0]) \(seconds) \(parts[2])")
    }
}

/// Finds the reports macOS wrote about GlassWork and its widgets.
public enum CrashReportFolder {
    public static let processes = ["GlassWork", "GlassWorkWidgets"]

    public static var defaultURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/DiagnosticReports", directoryHint: .isDirectory)
    }

    /// Reports written after `date`, oldest first.
    public static func reports(in folder: URL = defaultURL, after date: Date) -> [(url: URL, written: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return files.compactMap { url -> (url: URL, written: Date)? in
            let name = url.lastPathComponent
            guard url.pathExtension == "ips", processes.contains(where: { name.hasPrefix($0 + "-") }),
                  let written = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate,
                  written > date
            else { return nil }
            return (url, written)
        }
        .sorted { $0.written < $1.written }
    }
}
