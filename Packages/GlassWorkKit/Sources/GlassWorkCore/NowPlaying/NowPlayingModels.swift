import Foundation

/// A song in the player's queue.
public struct NowPlayingTrack: Codable, Sendable, Equatable {
    public var title: String
    public var artist: String?
    public var album: String?
    /// Nil when the player does not say. Live streams report zero.
    public var duration: TimeInterval?

    public init(title: String, artist: String? = nil, album: String? = nil, duration: TimeInterval? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }
}

/// What the system's Now Playing session reports at one moment.
public struct NowPlayingSession: Codable, Sendable, Equatable {
    public var track: NowPlayingTrack
    public var isPlaying: Bool
    /// The position at `elapsedAt`. Players report it only now and then, so it has to be carried forward.
    public var elapsed: TimeInterval
    public var elapsedAt: Date
    public var appName: String?
    /// The app itself, even when a helper process of a browser does the playing.
    public var bundleID: String?
    public var canGoNext = false
    public var canGoPrevious = false
    public var canSeek = false
    public var queue: [NowPlayingTrack] = []
    public var artworkID: String?
    /// From the player, or found online for a player that sends none.
    public var lyrics: [String] = []
    /// When each line starts. Empty when the lyrics carry no timing.
    public var lyricStarts: [TimeInterval] = []

    public init(
        track: NowPlayingTrack,
        isPlaying: Bool,
        elapsed: TimeInterval = 0,
        elapsedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.track = track
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.elapsedAt = elapsedAt
    }

    /// The player's name, or the last part of its bundle identifier when it gives none.
    public var sourceName: String? {
        appName ?? bundleID?.split(separator: ".").last.map(String.init)
    }

    /// Where playback is. Follows `isPlaying`: VLC keeps reporting a rate of 1 while paused.
    public func position(at date: Date) -> TimeInterval {
        let moved = isPlaying ? max(date.timeIntervalSince(elapsedAt), 0) : 0
        let position = elapsed + moved
        return track.duration.map { min(position, $0) } ?? position
    }

    public func progress(at date: Date) -> Double? {
        track.duration.map { position(at: date) / $0 }
    }

    /// The moment the track ends if nothing changes, or nil when that cannot be told.
    public func endDate(from date: Date) -> Date? {
        guard isPlaying, let duration = track.duration else { return nil }
        return date.addingTimeInterval(max(duration - position(at: date), 0))
    }

    /// True when a widget would show something else. A player that only re-reports
    /// its position, as VLC does every second, is not a change.
    public func looksDifferent(from other: NowPlayingSession) -> Bool {
        guard track == other.track, isPlaying == other.isPlaying, artworkID == other.artworkID,
              lyrics == other.lyrics, queue == other.queue
        else { return true }
        return abs(position(at: elapsedAt) - other.position(at: elapsedAt)) > Self.seekThreshold
    }

    private static let seekThreshold: TimeInterval = 3
}

/// A transport button. The adapter takes these as text, one per line.
public enum NowPlayingCommand: Codable, Sendable, Equatable {
    case play, pause, toggle, next, previous
    case seek(TimeInterval)

    public var line: String {
        switch self {
        case .play: "play"
        case .pause: "pause"
        case .toggle: "toggle"
        case .next: "next"
        case .previous: "previous"
        case let .seek(seconds): String(format: "seek %.3f", locale: Locale(identifier: "en_US_POSIX"), max(seconds, 0))
        }
    }
}

/// The lyric line to highlight. Without timing the line is estimated:
/// each line gets a share of the track in proportion to its length.
public enum LyricsTiming {
    /// The last line that has started. Before the first one, that first line.
    public static func lineIndex(starts: [TimeInterval], position: TimeInterval) -> Int? {
        guard !starts.isEmpty else { return nil }
        return starts.lastIndex { $0 <= position } ?? 0
    }

    public static func lineIndex(in lines: [String], progress: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        let total = Double(lines.reduce(0) { $0 + $1.count })
        guard total > 0 else { return 0 }
        var passed = 0.0
        let target = min(max(progress, 0), 1) * total
        for (index, line) in lines.enumerated() {
            passed += Double(line.count)
            if target < passed {
                return index
            }
        }
        return lines.count - 1
    }

    /// When each line after the current one begins, as offsets into the track.
    public static func lineStarts(in lines: [String], duration: TimeInterval) -> [TimeInterval] {
        let total = Double(lines.reduce(0) { $0 + $1.count })
        guard total > 0 else { return [] }
        var passed = 0.0
        return lines.map { line in
            defer { passed += Double(line.count) }
            return passed / total * duration
        }
    }
}
