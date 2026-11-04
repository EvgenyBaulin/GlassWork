import Foundation

/// Song lyrics, with the moment each line starts when the source gives it.
public struct FoundLyrics: Sendable, Equatable {
    public var lines: [String]
    /// One offset per line, or empty for lyrics without timing.
    public var starts: [TimeInterval]

    public init(lines: [String], starts: [TimeInterval] = []) {
        self.lines = lines
        self.starts = starts
    }
}

/// Asks lrclib.net for lyrics. Only the title, artist, album and length of the song are sent.
public enum LRCLib {
    private struct Response: Decodable {
        var instrumental: Bool?
        var plainLyrics: String?
        var syncedLyrics: String?
    }

    /// The address to ask, or nil for a track too vague to look up.
    public static func url(for track: NowPlayingTrack) -> URL? {
        guard !track.title.isEmpty, let artist = track.artist, !artist.isEmpty else { return nil }
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        if let album = track.album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration = track.duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: "\(Int(duration.rounded()))"))
        }
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = items
        return components?.url
    }

    /// Timed lines win over plain ones. Nil when there is nothing to show.
    public static func lyrics(from data: Data) -> FoundLyrics? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.instrumental != true
        else { return nil }
        if let timed = response.syncedLyrics.flatMap(timedLyrics), !timed.lines.isEmpty {
            return timed
        }
        let plain = (response.plainLyrics ?? "").split(whereSeparator: \.isNewline).map(String.init)
        return plain.isEmpty ? nil : FoundLyrics(lines: plain)
    }

    /// Reads `[mm:ss.xx] line`. A line with no words is a pause, so the line before it stays up.
    static func timedLyrics(_ text: String) -> FoundLyrics? {
        var found: [(start: TimeInterval, line: String)] = []
        for row in text.split(whereSeparator: \.isNewline) {
            guard let match = row.wholeMatch(of: /\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)/),
                  let minutes = Double(match.1), let seconds = Double(match.2)
            else { continue }
            let line = String(match.3).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty {
                found.append((minutes * 60 + seconds, line))
            }
        }
        guard !found.isEmpty else { return nil }
        return FoundLyrics(lines: found.map(\.line), starts: found.map(\.start))
    }
}
