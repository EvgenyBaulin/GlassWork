import Foundation

/// What the log may record. A closed list on purpose: error messages carry paths and user names, so no free text
/// can get in. Nothing here says what the user copied, played, typed or opened.
public enum DiagnosticEvent: Sendable, Equatable {
    case logStarted(version: String)
    case settingsProblem
    case shortcutRefused(action: String)
    case gitHubFailed(status: Int32)

    var line: String {
        switch self {
        case let .logStarted(version): "log started, version \(Self.safe(version))"
        case .settingsProblem: "settings file could not be read or saved"
        case let .shortcutRefused(action): "shortcut refused by macOS: \(Self.safe(action))"
        case let .gitHubFailed(status): "gh failed with status \(status)"
        }
    }

    /// These values are identifiers and version numbers; anything else in them is dropped.
    private static func safe(_ text: String) -> String {
        String(text.filter { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }.prefix(40))
    }
}

/// An opt-in local log. While it is off nothing touches the disk, and turning it off deletes the file.
/// Nothing here sends it anywhere: only the user's own "Send to developer…" does, through a Mail draft.
public actor DiagnosticLog {
    public static let keepDays = 7
    public static let sizeLimit = 512_000

    public static var defaultURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appending(path: "Logs/GlassWork/diagnostic.log", directoryHint: .notDirectory)
    }

    private let url: URL
    private var isOn = false
    private var lastPrune: Date?

    public init(url: URL = DiagnosticLog.defaultURL) {
        self.url = url
    }

    public func setEnabled(_ value: Bool, at date: Date = Date()) {
        guard value != isOn else { return }
        isOn = value
        if value {
            prune(at: date)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    public func record(_ event: DiagnosticEvent, at date: Date = Date()) {
        guard isOn else { return }
        if isDueForPruning(at: date) {
            prune(at: date)
        }
        append("\(date.formatted(.iso8601))\t\(event.line)\n")
    }

    private func isDueForPruning(at date: Date) -> Bool {
        guard let lastPrune else { return true }
        return date.timeIntervalSince(lastPrune) >= 86400 || Self.size(of: url) > Self.sizeLimit
    }

    private func append(_ line: String) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? Data(line.utf8).write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Drops what is past its week, then the oldest lines until the file is well under the limit.
    private func prune(at date: Date) {
        lastPrune = date
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let oldest = date.addingTimeInterval(-TimeInterval(Self.keepDays) * 86400)
        var lines = text.split(separator: "\n").filter { line in
            guard let stamp = line.split(separator: "\t").first,
                  let written = try? Date(String(stamp), strategy: .iso8601)
            else { return false }
            return written >= oldest
        }
        var total = lines.reduce(0) { $0 + $1.utf8.count + 1 }
        while total > Self.sizeLimit / 2, let first = lines.first {
            total -= first.utf8.count + 1
            lines.removeFirst()
        }
        let kept = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        try? Data(kept.utf8).write(to: url, options: .atomic)
    }

    /// Zero when there is no file yet.
    public nonisolated static func size(of url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? Int) ?? 0
    }
}
