import CoreGraphics
import Foundation
@testable import GlassWorkCore
import ImageIO
import Testing

private func events(_ fixture: String) throws -> [NowPlayingEvent] {
    try textFixture(fixture).split(separator: "\n").compactMap { NowPlayingParser.parse(String($0)) }
}

private func sessions(_ fixture: String) throws -> [NowPlayingSession] {
    try events(fixture).compactMap {
        if case let .session(session?) = $0 {
            return session
        }
        return nil
    }
}

struct NowPlayingParserTests {
    @Test func readsARealPlayerSession() throws {
        let session = try #require(sessions("now-playing-public-api.jsonl").first)
        #expect(session.track.title == "Harness Song 0")
        #expect(session.track.artist == "Тест Артист")
        #expect(session.track.album == "Album \"Q\"")
        #expect(session.track.duration == 200)
        #expect(session.isPlaying)
        #expect(session.canGoNext && session.canGoPrevious && session.canSeek)
        #expect(session.artworkID == "7edc938ebe1aeaba")
        #expect(session.lyrics.isEmpty)
    }

    @Test func timestampsCountFromTheReferenceDate() throws {
        let session = try #require(sessions("now-playing-public-api.jsonl").first)
        #expect(Calendar(identifier: .gregorian).component(.year, from: session.elapsedAt) == 2026)
    }

    @Test func noPlayerMeansNoSession() throws {
        let last = try #require(events("now-playing-public-api.jsonl").last)
        #expect(last == .session(nil))
    }

    @Test func artworkIsDecoded() throws {
        let found = try events("now-playing-public-api.jsonl").contains {
            if case let .artwork(id, data) = $0 {
                return id == "7edc938ebe1aeaba" && data.starts(with: [0xFF, 0xD8])
            }
            return false
        }
        #expect(found)
    }

    @Test func vlcPausesAndSeeks() throws {
        let all = try sessions("now-playing-vlc.jsonl")
        #expect(all.first?.appName == "VLC")
        #expect(all.contains { !$0.isPlaying })
        #expect(all.contains { $0.elapsed == 30 })
    }

    @Test func zeroDurationIsUnknown() throws {
        // VLC reports zero until the file is open.
        let first = try #require(sessions("now-playing-vlc.jsonl").first)
        #expect(first.track.duration == nil)
        #expect(first.progress(at: first.elapsedAt) == nil)
        #expect(first.endDate(from: first.elapsedAt) == nil)
    }

    @Test func aHelperProcessCountsAsItsApp() {
        let line = """
        {"event":"state","isActive":true,"isPlaying":true,"title":"Video","elapsed":1,"elapsedAt":815467000,\
        "bundleID":"com.apple.WebKit.GPU","parentBundleID":"com.apple.Safari"}
        """
        guard case let .session(session?) = NowPlayingParser.parse(line) else {
            Issue.record("no session")
            return
        }
        #expect(session.bundleID == "com.apple.Safari")
        #expect(session.sourceName == "Safari")
    }

    @Test func aPlayerWithoutATrackIsNoSession() {
        let line = #"{"event":"state","isActive":true,"isPlaying":false,"bundleID":"org.videolan.vlc"}"#
        #expect(NowPlayingParser.parse(line) == .session(nil))
    }

    @Test func lyricsBecomeLines() {
        let line = #"{"event":"state","isActive":true,"title":"T","lyrics":"first\n\n  second  \r\nthird\n"}"#
        guard case let .session(session?) = NowPlayingParser.parse(line) else {
            Issue.record("no session")
            return
        }
        #expect(session.lyrics == ["first", "second", "third"])
    }

    @Test func queueSkipsUntitledItems() {
        let line = """
        {"event":"state","isActive":true,"title":"T","queue":[{"title":"Next","artist":"A","duration":200},\
        {"artist":"B"},{"title":"Live","duration":0}]}
        """
        guard case let .session(session?) = NowPlayingParser.parse(line) else {
            Issue.record("no session")
            return
        }
        #expect(session.queue == [
            NowPlayingTrack(title: "Next", artist: "A", duration: 200),
            NowPlayingTrack(title: "Live"),
        ])
    }

    @Test func unavailableKeepsTheReason() {
        #expect(NowPlayingParser.parse(#"{"event":"unavailable","reason":"no"}"#) == .unavailable("no"))
    }

    @Test func noiseIsIgnored() {
        #expect(NowPlayingParser.parse("not json") == nil)
        #expect(NowPlayingParser.parse(#"{"event":"other"}"#) == nil)
        #expect(NowPlayingParser.parse(#"{"event":"artwork","id":"1","data":"%%%"}"#) == nil)
    }
}

struct LineBufferTests {
    @Test func joinsLinesThatArriveInPieces() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("{\"a\"".utf8)).isEmpty)
        #expect(buffer.append(Data(":1}\n{\"b\":2}\n{\"c".utf8)) == ["{\"a\":1}", "{\"b\":2}"])
        #expect(buffer.append(Data("\":3}\n".utf8)) == ["{\"c\":3}"])
    }

    @Test func keepsMultibyteTextSplitBetweenReads() {
        var buffer = LineBuffer()
        let bytes = Data("Тест\n".utf8)
        #expect(buffer.append(bytes.prefix(3)).isEmpty)
        #expect(buffer.append(bytes.dropFirst(3)) == ["Тест"])
    }
}

struct NowPlayingSessionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(playing: Bool = true, elapsed: TimeInterval = 10) -> NowPlayingSession {
        NowPlayingSession(
            track: NowPlayingTrack(title: "T", duration: 100),
            isPlaying: playing,
            elapsed: elapsed,
            elapsedAt: start
        )
    }

    @Test func positionMovesOnlyWhilePlaying() {
        let later = start.addingTimeInterval(5)
        #expect(session().position(at: later) == 15)
        #expect(session(playing: false).position(at: later) == 10)
    }

    @Test func positionStopsAtTheEnd() {
        #expect(session().position(at: start.addingTimeInterval(1000)) == 100)
        #expect(session().progress(at: start.addingTimeInterval(40)) == 0.5)
    }

    @Test func positionNeverRunsBackwards() {
        #expect(session().position(at: start.addingTimeInterval(-5)) == 10)
    }

    @Test func endDateFollowsThePosition() {
        #expect(session().endDate(from: start) == start.addingTimeInterval(90))
        #expect(session(playing: false).endDate(from: start) == nil)
    }

    @Test func positionReportsAreNotAChange() throws {
        let all = try sessions("now-playing-vlc.jsonl")
        // Pause, resume, one plain position report, the seek to 30 s and the jump to the start of the next track.
        let changes = zip(all, all.dropFirst()).filter { $1.looksDifferent(from: $0) }.count
        #expect(changes < all.count - 1)
        var moved = session()
        moved.elapsed = 12
        moved.elapsedAt = start.addingTimeInterval(2)
        #expect(!moved.looksDifferent(from: session()))
    }

    @Test func aSeekIsAChange() {
        #expect(session(elapsed: 40).looksDifferent(from: session()))
    }

    @Test func pausingIsAChange() {
        #expect(session(playing: false).looksDifferent(from: session()))
    }

    @Test func commandsBecomeAdapterLines() {
        #expect(NowPlayingCommand.toggle.line == "toggle")
        #expect(NowPlayingCommand.seek(30.5).line == "seek 30.500")
        #expect(NowPlayingCommand.seek(-1).line == "seek 0.000")
    }
}

struct LyricsTimingTests {
    @Test func theLineFollowsProgressByLength() {
        let lines = ["aaaa", "bb", "bb"]
        #expect(LyricsTiming.lineIndex(in: lines, progress: 0) == 0)
        #expect(LyricsTiming.lineIndex(in: lines, progress: 0.49) == 0)
        #expect(LyricsTiming.lineIndex(in: lines, progress: 0.5) == 1)
        #expect(LyricsTiming.lineIndex(in: lines, progress: 0.8) == 2)
        #expect(LyricsTiming.lineIndex(in: lines, progress: 1) == 2)
    }

    @Test func noLinesNoIndex() {
        #expect(LyricsTiming.lineIndex(in: [], progress: 0.5) == nil)
    }

    @Test func startsMatchTheIndex() {
        let lines = ["aaaa", "bb", "bb"]
        let starts = LyricsTiming.lineStarts(in: lines, duration: 80)
        #expect(starts == [0, 40, 60])
        for (index, start) in starts.enumerated() {
            #expect(LyricsTiming.lineIndex(in: lines, progress: start / 80) == index)
        }
    }
}

struct ArtworkImageTests {
    private func image(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let cgImage = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func largeArtworkIsScaledDown() throws {
        let fitted = try #require(ArtworkImage.fitted(image(side: 1000)))
        let source = try #require(CGImageSourceCreateWithData(fitted as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) == ArtworkImage.pixels)
        #expect(fitted.starts(with: [0xFF, 0xD8]))
    }

    @Test func notAnImage() {
        #expect(ArtworkImage.fitted(Data("hello".utf8)) == nil)
    }
}

struct NowPlayingSnapshotsTests {
    private func store() -> SnapshotStore {
        SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "GlassWorkTests-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    private var session: NowPlayingSession {
        var session = NowPlayingSession(track: NowPlayingTrack(title: "T"), isPlaying: true)
        session.artworkID = "a"
        return session
    }

    @Test func roundTripWithArtwork() throws {
        let snapshots = NowPlayingSnapshots(store: store())
        let data = NowPlayingWidgetData(session: session, artwork: Data([1, 2, 3]), outputDevice: "Speakers")
        try snapshots.write(data)
        #expect(snapshots.read() == data)
    }

    @Test func artworkIsReadOnlyForATrackThatHasIt() throws {
        let snapshots = NowPlayingSnapshots(store: store())
        try snapshots.write(NowPlayingWidgetData(session: session, artwork: Data([1])))
        var plain = session
        plain.artworkID = nil
        try snapshots.write(NowPlayingWidgetData(session: plain))
        #expect(snapshots.read()?.artwork == nil)
    }

    @Test func idleClearsTheRecord() throws {
        let snapshots = NowPlayingSnapshots(store: store())
        try snapshots.write(NowPlayingWidgetData(session: session))
        try snapshots.write(nil)
        #expect(snapshots.read() == nil)
    }

    @Test func oldRequestsAreNotActedOn() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let request = NowPlayingRequest(command: .toggle, date: date)
        #expect(request.isFresh(at: date.addingTimeInterval(1)))
        #expect(!request.isFresh(at: date.addingTimeInterval(60)))
    }
}

struct ReloadThrottleTests {
    @Test func theFirstReloadIsImmediateAndTheNextWaits() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var throttle = ReloadThrottle(interval: 60)
        #expect(throttle.delay(at: date) == 0)
        #expect(throttle.delay(at: date.addingTimeInterval(20)) == 40)
        #expect(throttle.delay(at: date.addingTimeInterval(60)) == 0)
    }
}

/// Answers with lines the test decides and records what it was told.
private final class FakeSource: NowPlayingSource, @unchecked Sendable {
    // Why unchecked: tests touch it from the main actor only; the callbacks are stored once.
    var sent: [String] = []
    var isRunning = false
    var starts = 0
    var onLine: (@Sendable (String) -> Void)?
    var onExit: (@Sendable (Int32) -> Void)?

    func start(onLine: @escaping @Sendable (String) -> Void, onExit: @escaping @Sendable (Int32) -> Void) throws {
        self.onLine = onLine
        self.onExit = onExit
        isRunning = true
        starts += 1
    }

    func send(_ line: String) {
        sent.append(line)
    }

    func stop() {
        isRunning = false
    }
}

@MainActor
struct NowPlayingStoreTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)
    private let fake = FakeSource()

    private func makeStore() -> NowPlayingStore {
        let fake = fake
        return NowPlayingStore(makeSource: { fake })
    }

    private func session(_ title: String = "T", artwork: String? = nil) -> NowPlayingSession {
        var session = NowPlayingSession(track: NowPlayingTrack(title: title), isPlaying: true, elapsedAt: date)
        session.artworkID = artwork
        return session
    }

    @Test func runsOnlyWhileWanted() {
        let store = makeStore()
        store.tick(wanted: false, at: date)
        #expect(!fake.isRunning)
        store.tick(wanted: true, at: date)
        #expect(fake.isRunning)
        store.tick(wanted: true, at: date)
        #expect(fake.starts == 1)
        store.tick(wanted: false, at: date)
        #expect(!fake.isRunning)
    }

    @Test func aCommandStartsTheAdapterForAWhile() {
        let store = makeStore()
        store.perform(.next, at: date)
        #expect(fake.isRunning)
        #expect(fake.sent == ["next"])
        store.tick(wanted: false, at: date.addingTimeInterval(5))
        #expect(fake.isRunning)
        store.tick(wanted: false, at: date.addingTimeInterval(60))
        #expect(!fake.isRunning)
    }

    @Test func nothingIsClaimedBeforeTheFirstAnswer() {
        let store = makeStore()
        #expect(!store.hasLoaded)
        store.apply(.session(nil))
        #expect(store.hasLoaded)
    }

    @Test func artworkBelongsToItsTrack() {
        let store = makeStore()
        store.apply(.session(session(artwork: "a")))
        store.apply(.artwork(id: "other", data: Data()))
        #expect(store.artwork == nil)
        store.apply(.session(session("Next", artwork: "b")))
        #expect(store.session?.artworkID == "b")
    }

    @Test func aNewTrackDropsTheOldArtwork() throws {
        let store = makeStore()
        store.apply(.session(session(artwork: "a")))
        let png = try #require(Data(base64Encoded: Self.onePixelPNG))
        store.apply(.artwork(id: "a", data: png))
        #expect(store.artwork != nil)
        store.apply(.session(session("Next", artwork: "b")))
        #expect(store.artwork == nil)
    }

    @Test func onlyVisibleChangesAreReported() {
        let store = makeStore()
        var changes = 0
        store.onChange = { changes += 1 }
        store.apply(.session(session()))
        #expect(changes == 1)
        store.apply(.session(session()))
        #expect(changes == 1)
        store.apply(.session(session("Next")))
        #expect(changes == 2)
        store.apply(.session(nil))
        #expect(changes == 3)
        store.apply(.session(nil))
        #expect(changes == 3)
    }

    @Test func theAppNameComesFromTheBundleWhenKnown() {
        var lookups = 0
        let store = NowPlayingStore(appName: { _ in
            lookups += 1
            return "Safari"
        })
        var reported = session()
        reported.bundleID = "com.apple.Safari"
        reported.appName = "Safari Graphics and Media"
        store.apply(.session(reported))
        store.apply(.session(reported))
        #expect(store.session?.appName == "Safari")
        #expect(lookups == 1)
    }

    @Test func unavailableStopsRetrying() async {
        let store = makeStore()
        store.tick(wanted: true, at: date)
        fake.onExit?(3)
        await waitUntil { store.isUnavailable }
        store.tick(wanted: true, at: date.addingTimeInterval(1000))
        #expect(fake.starts == 1)
    }

    @Test func aCrashRestartsAfterAWaitThatGrows() async {
        let store = makeStore()
        store.tick(wanted: true, at: date)
        fake.onExit?(255)
        await waitUntil { !store.isRunning }
        let crash = Date()
        store.tick(wanted: true, at: crash.addingTimeInterval(1))
        #expect(fake.starts == 1)
        store.tick(wanted: true, at: crash.addingTimeInterval(6))
        #expect(fake.starts == 2)
        fake.onExit?(255)
        await waitUntil { !store.isRunning }
        store.tick(wanted: true, at: Date().addingTimeInterval(6))
        #expect(fake.starts == 2)
    }

    @Test func linesFromAStoppedAdapterAreDropped() async throws {
        let store = makeStore()
        store.tick(wanted: true, at: date)
        let late = try #require(fake.onLine)
        store.stop()
        late(#"{"event":"state","isActive":true,"title":"Late"}"#)
        await Task.yield()
        #expect(store.session == nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 200 where !condition() {
            await Task.yield()
        }
        #expect(condition())
    }

    private static let onePixelPNG = """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==
    """
}

/// The real process wrapper around ordinary system tools. No media is involved.
struct NowPlayingAdapterTests {
    private final class Collector: @unchecked Sendable {
        // Why unchecked: the lock guards both values.
        private let lock = NSLock()
        private var lines: [String] = []
        private var status: Int32?

        func add(_ line: String) {
            lock.withLock { lines.append(line) }
        }

        func finish(_ value: Int32) {
            lock.withLock { status = value }
        }

        var received: [String] {
            lock.withLock { lines }
        }

        var exitStatus: Int32? {
            lock.withLock { status }
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0 ..< 400 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func linesGoInAndComeBack() async throws {
        let adapter = NowPlayingAdapter(executable: "/bin/cat", arguments: [])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        adapter.send("toggle")
        try await wait { !collector.received.isEmpty }
        #expect(collector.received == ["toggle"])
        adapter.stop()
    }

    @Test func theExitStatusIsReported() async throws {
        let adapter = NowPlayingAdapter(executable: "/bin/sh", arguments: ["-c", "exit 3"])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        try await wait { collector.exitStatus != nil }
        #expect(collector.exitStatus == 3)
    }

    @Test func writingToADeadProcessDoesNotKillTheApp() async throws {
        let adapter = NowPlayingAdapter(executable: "/usr/bin/true", arguments: [])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        try await wait { collector.exitStatus != nil }
        adapter.send("toggle")
        adapter.send("toggle")
        adapter.stop()
    }

    @Test func perlGetsAMinimalEnvironment() async throws {
        let code = #"print join(",", sort grep { !/^__CF/ } keys %ENV), "\n""#
        let adapter = NowPlayingAdapter(executable: "/usr/bin/perl", arguments: ["-e", code])
        let collector = Collector()
        try adapter.start(onLine: collector.add, onExit: collector.finish)
        try await wait { !collector.received.isEmpty }
        #expect(collector.received == ["LANG,PATH"])
    }

    @Test func theScriptCompiles() async throws {
        let script = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../../../../App/Resources/now-playing-adapter.pl")
            .standardized
        let output = try await ProcessRunner().run("/usr/bin/perl", arguments: ["-c", script.path], timeout: 20)
        #expect(output.status == 0)
        #expect(output.stderr.contains("syntax OK"))
    }
}
