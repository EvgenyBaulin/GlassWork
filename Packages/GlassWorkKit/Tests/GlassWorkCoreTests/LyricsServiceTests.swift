import Foundation
@testable import GlassWorkCore
import Testing

struct LRCLibTests {
    @Test func asksWithEverythingTheTrackKnows() throws {
        let track = NowPlayingTrack(title: "Песня & co", artist: "Кто-то", album: "Альбом", duration: 233.4)
        let url = try #require(LRCLib.url(for: track))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host() == "lrclib.net")
        #expect(items.first { $0.name == "track_name" }?.value == "Песня & co")
        #expect(items.first { $0.name == "artist_name" }?.value == "Кто-то")
        #expect(items.first { $0.name == "album_name" }?.value == "Альбом")
        #expect(items.first { $0.name == "duration" }?.value == "233")
    }

    @Test func aTrackWithoutAnArtistIsNotLookedUp() {
        #expect(LRCLib.url(for: NowPlayingTrack(title: "Stream")) == nil)
        #expect(LRCLib.url(for: NowPlayingTrack(title: "Stream", artist: "")) == nil)
    }

    @Test func timedLinesWinOverPlainOnes() throws {
        let json = """
        {"instrumental":false,"plainLyrics":"one\\ntwo",
        "syncedLyrics":"[00:01.50] one\\n[00:04.00] \\n[01:02.25] two\\n"}
        """
        let lyrics = try #require(LRCLib.lyrics(from: Data(json.utf8)))
        #expect(lyrics.lines == ["one", "two"])
        #expect(lyrics.starts == [1.5, 62.25])
    }

    @Test func plainLinesCarryNoTiming() throws {
        let json = #"{"instrumental":false,"plainLyrics":"one\n\ntwo","syncedLyrics":null}"#
        let lyrics = try #require(LRCLib.lyrics(from: Data(json.utf8)))
        #expect(lyrics.lines == ["one", "two"])
        #expect(lyrics.starts.isEmpty)
    }

    @Test func nothingToShowIsNil() {
        #expect(LRCLib.lyrics(from: Data(#"{"instrumental":true,"plainLyrics":null}"#.utf8)) == nil)
        #expect(LRCLib.lyrics(from: Data(#"{"message":"Failed to find specified track"}"#.utf8)) == nil)
        #expect(LRCLib.lyrics(from: Data("not json".utf8)) == nil)
    }

    @Test func theLineFollowsItsStartTime() {
        let starts: [TimeInterval] = [5, 10, 20]
        #expect(LyricsTiming.lineIndex(starts: starts, position: 1) == 0)
        #expect(LyricsTiming.lineIndex(starts: starts, position: 10) == 1)
        #expect(LyricsTiming.lineIndex(starts: starts, position: 99) == 2)
        #expect(LyricsTiming.lineIndex(starts: [], position: 1) == nil)
    }
}

private final class CountingFetcher: HTTPFetching, @unchecked Sendable {
    // @unchecked: `urls` is guarded by `lock`, the reply is immutable.
    private let lock = NSLock()
    private var urls: [URL] = []
    private let reply: Data

    init(_ reply: String) {
        self.reply = Data(reply.utf8)
    }

    var count: Int {
        lock.withLock { urls.count }
    }

    func data(from url: URL) async throws -> Data {
        lock.withLock { urls.append(url) }
        return reply
    }
}

@MainActor
struct OnlineLyricsTests {
    private static let reply = #"{"syncedLyrics":"[00:01.00] one\n[00:02.00] two"}"#

    private func session(_ title: String = "Song", lyrics: [String] = []) -> NowPlayingSession {
        var session = NowPlayingSession(
            track: NowPlayingTrack(title: title, artist: "Artist", duration: 100),
            isPlaying: true
        )
        session.lyrics = lyrics
        return session
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0 ..< 200 where !done() {
            await Task.yield()
        }
    }

    @Test func nothingIsSentUnlessAWidgetWantsLyrics() async {
        let fetcher = CountingFetcher(Self.reply)
        let store = NowPlayingStore(lyricsFetcher: fetcher)
        store.apply(.session(session()))
        await settle { fetcher.count > 0 }
        #expect(fetcher.count == 0)
    }

    @Test func aTrackIsAskedForOnceAndKeepsItsLinesAcrossReports() async {
        let fetcher = CountingFetcher(Self.reply)
        let store = NowPlayingStore(lyricsFetcher: fetcher)
        store.wantsLyrics = true
        store.apply(.session(session()))
        await settle { store.session?.lyrics.isEmpty == false }
        #expect(store.session?.lyrics == ["one", "two"])
        #expect(store.session?.lyricStarts == [1, 2])

        store.apply(.session(session()))
        #expect(store.session?.lyrics == ["one", "two"])
        #expect(fetcher.count == 1)
    }

    @Test func aNewTrackDoesNotKeepTheOldLines() async {
        let fetcher = CountingFetcher("{}")
        let store = NowPlayingStore(lyricsFetcher: fetcher)
        store.wantsLyrics = true
        store.apply(.session(session()))
        store.apply(.session(session("Other")))
        await settle { fetcher.count == 2 }
        #expect(fetcher.count == 2)
        #expect(store.session?.lyrics.isEmpty == true)
    }

    @Test func thePlayersOwnLyricsWin() async {
        let fetcher = CountingFetcher(Self.reply)
        let store = NowPlayingStore(lyricsFetcher: fetcher)
        store.wantsLyrics = true
        store.apply(.session(session(lyrics: ["mine"])))
        await settle { fetcher.count > 0 }
        #expect(fetcher.count == 0)
        #expect(store.session?.lyrics == ["mine"])
    }
}
