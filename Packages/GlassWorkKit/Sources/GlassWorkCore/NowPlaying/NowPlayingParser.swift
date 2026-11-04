import Foundation

/// One line of the adapter's output.
public enum NowPlayingEvent: Sendable, Equatable {
    /// Nil when no app is playing anything.
    case session(NowPlayingSession?)
    case artwork(id: String, data: Data)
    case unavailable(String)
}

/// Reads the adapter's JSON lines.
public enum NowPlayingParser {
    private struct Line: Decodable {
        var event: String
        var isActive: Bool?
        var isPlaying: Bool?
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
        var elapsed: Double?
        var elapsedAt: Double?
        var bundleID: String?
        var parentBundleID: String?
        var appName: String?
        var canGoNext: Bool?
        var canGoPrevious: Bool?
        var canSeek: Bool?
        var artworkID: String?
        var lyrics: String?
        var queue: [QueueItem]?
        var id: String?
        var data: String?
        var reason: String?
    }

    private struct QueueItem: Decodable {
        var title: String?
        var artist: String?
        var album: String?
        var duration: Double?
    }

    public static func parse(_ text: String) -> NowPlayingEvent? {
        guard let line = try? JSONDecoder().decode(Line.self, from: Data(text.utf8)) else { return nil }
        switch line.event {
        case "state":
            return .session(session(from: line))
        case "artwork":
            guard let id = line.id, let data = line.data.flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return .artwork(id: id, data: data)
        case "unavailable":
            return .unavailable(line.reason ?? "")
        default:
            return nil
        }
    }

    private static func session(from line: Line) -> NowPlayingSession? {
        guard line.isActive == true, let title = line.title else { return nil }
        var session = NowPlayingSession(
            track: NowPlayingTrack(
                title: title,
                artist: line.artist,
                album: line.album,
                duration: known(line.duration)
            ),
            isPlaying: line.isPlaying ?? false,
            elapsed: line.elapsed ?? 0,
            elapsedAt: Date(timeIntervalSinceReferenceDate: line.elapsedAt ?? 0)
        )
        session.appName = line.appName
        session.bundleID = line.parentBundleID ?? line.bundleID
        session.canGoNext = line.canGoNext ?? false
        session.canGoPrevious = line.canGoPrevious ?? false
        session.canSeek = line.canSeek ?? false
        session.artworkID = line.artworkID
        session.lyrics = lyricLines(line.lyrics)
        session.queue = (line.queue ?? []).compactMap { item in
            item.title.map {
                NowPlayingTrack(title: $0, artist: item.artist, album: item.album, duration: known(item.duration))
            }
        }
        return session
    }

    /// Players report zero for a live stream or a track still loading.
    private static func known(_ duration: Double?) -> TimeInterval? {
        duration.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func lyricLines(_ text: String?) -> [String] {
        (text ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// Splits a byte stream into lines. Artwork lines arrive in many pieces.
public struct LineBuffer: Sendable {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let end = pending.firstIndex(of: 0x0A) {
            lines.append(String(decoding: pending[pending.startIndex ..< end], as: UTF8.self))
            pending.removeSubrange(pending.startIndex ... end)
        }
        return lines
    }
}
