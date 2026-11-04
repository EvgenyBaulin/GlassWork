import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

private let now = Date(timeIntervalSince1970: 1_793_750_000)

/// A colored square standing in for album art.
@MainActor
private let cover: Data? = {
    let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        NSGradient(starting: .systemOrange, ending: .systemPink)?.draw(in: rect, angle: 45)
        return true
    }
    return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?.representation(using: .png, properties: [:])
}()

private func track(queue: Bool = true, lyrics: Bool = false, playing: Bool = true) -> NowPlayingSession {
    var session = NowPlayingSession(
        track: NowPlayingTrack(
            title: "Northern Lights",
            artist: "Paper Satellites",
            album: "Static Bloom",
            duration: 240
        ),
        isPlaying: playing,
        elapsed: 168,
        elapsedAt: now
    )
    session.appName = "Music"
    session.bundleID = "com.apple.Music"
    session.canGoNext = true
    session.canGoPrevious = true
    session.canSeek = true
    session.artworkID = "cover"
    if queue {
        session.queue = [
            NowPlayingTrack(title: "Paper Kites", artist: "Low Tide Choir", duration: 221),
            NowPlayingTrack(title: "Glass Harbour", artist: "Mira Vale", duration: 245),
            NowPlayingTrack(title: "Slow Satellites", artist: "Paper Satellites", duration: 192),
            NowPlayingTrack(title: "Copper Rain", artist: "The Long Weekend", duration: 238),
            NowPlayingTrack(title: "Quiet Engines", artist: "Northfield", duration: 262),
            NowPlayingTrack(title: "Lanterns", artist: "Ada & the Owls", duration: 179),
        ]
    }
    if lyrics {
        session.lyrics = [
            "We drew the map on a paper sky",
            "and followed every falling light",
            "the city hums a quiet tune",
            "under a borrowed silver moon",
            "hold on, the night is wide awake",
            "we've got the morning left to make",
            "so leave the porch light burning low",
            "and sing the only song we know",
        ]
    }
    return session
}

/// The Now Playing and Lyrics widgets in every size and both themes.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct NowPlayingWidgetSnapshotTests {
    private func render(_ kind: WidgetKind, _ data: NowPlayingWidgetData?, state: String) {
        var snapshot = WidgetSnapshot(date: now)
        snapshot.nowPlaying = data
        for size in WidgetSize.allCases {
            for dark in [true, false] {
                let view = WidgetFace(kind: kind, size: size, snapshot: snapshot, now: now)
                    .padding(16)
                    .frame(width: size.width, height: size.height)
                    .background(dark ? Color(red: 0.13, green: 0.12, blue: 0.19) : Color(white: 0.96))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: view)
                host.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let name = "\(kind.rawValue)-\(state)-\(size.rawValue)-\(dark ? "dark" : "light")"
                let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
                withSnapshotTesting(record: record ? .all : .missing) {
                    assertSnapshot(of: host, as: .image(precision: 0.98), named: name)
                }
            }
        }
    }

    @Test func playing() {
        let data = NowPlayingWidgetData(session: track(), artwork: cover, outputDevice: "MacBook Pro Speakers")
        render(.nowPlaying, data, state: "playing")
    }

    @Test func pausedWithoutQueueOrCover() {
        var session = track(queue: false, playing: false)
        session.artworkID = nil
        render(.nowPlaying, NowPlayingWidgetData(session: session), state: "paused")
    }

    @Test func unknownLengthHidesTheBar() {
        var session = track(queue: false)
        session.track.duration = nil
        render(.nowPlaying, NowPlayingWidgetData(session: session), state: "stream")
    }

    @Test func nothingPlaying() {
        render(.nowPlaying, nil, state: "idle")
    }

    @Test func lyrics() {
        render(.lyrics, NowPlayingWidgetData(session: track(lyrics: true), artwork: cover), state: "lines")
    }

    @Test func noLyrics() {
        render(.lyrics, NowPlayingWidgetData(session: track(), artwork: cover), state: "none")
    }

    @Test func lyricsWithNothingPlaying() {
        render(.lyrics, nil, state: "idle")
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct NowPlayingPanelSnapshotTests {
    private func store(_ session: NowPlayingSession?) -> NowPlayingStore {
        let store = NowPlayingStore()
        store.apply(.session(session))
        if let cover {
            store.apply(.artwork(id: "cover", data: cover))
        }
        return store
    }

    @Test(arguments: [true, false])
    func playing(dark: Bool) {
        assertPanel(NowPlayingPanel(store: store(track()), fixedNow: now), dark: dark, name: "now-playing-panel")
    }

    @Test(arguments: [true, false])
    func nothingPlaying(dark: Bool) {
        assertPanel(NowPlayingPanel(store: store(nil), fixedNow: now), dark: dark, name: "now-playing-panel-idle")
    }

    @Test(arguments: [true, false])
    func macOSRefused(dark: Bool) {
        let store = NowPlayingStore()
        store.apply(.unavailable("no"))
        assertPanel(NowPlayingPanel(store: store, fixedNow: now), dark: dark, name: "now-playing-panel-unavailable")
    }

    @Test(arguments: [true, false])
    func scrubberReadsTheTimeUnderTheCursor(dark: Bool) {
        let view = PlaybackScrubber(session: track(), now: now, initialHover: 0.25) { _ in }
            .padding(16)
            .padding(.top, 36)
        assertPanel(view, dark: dark, name: "now-playing-scrubber-hover")
    }
}

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct NowPlayingItemSnapshotTests {
    private func assertItem(_ store: NowPlayingStore, style: DisplayStyle, dark: Bool, name: String) {
        let monitor = SystemMonitor(nowPlaying: store)
        let options = [ModuleOption.hideWhenIdle: "false"]
        let renderer = MenuBarItemRenderer(
            module: .nowPlaying,
            style: style,
            numbers: .compact,
            options: options,
            monitor: monitor
        )
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        renderer.appearance = appearance
        let width = MenuBarItemView.width(
            module: .nowPlaying,
            style: style,
            numbers: .compact,
            options: options,
            monitor: monitor
        )
        let view = NSImageView(frame: CGRect(x: 0, y: 0, width: width, height: 24))
        view.image = renderer.image(size: CGSize(width: width, height: 24), force: true)
        view.contentTintColor = .labelColor
        view.appearance = appearance
        view.wantsLayer = true
        view.layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).cgColor
        let record = ProcessInfo.processInfo.environment["GW_RECORD_SNAPSHOTS"] != nil
        withSnapshotTesting(record: record ? .all : .missing) {
            assertSnapshot(of: view, as: .image(precision: 0.98), named: "\(name)-\(dark ? "dark" : "light")")
        }
    }

    private func store(_ session: NowPlayingSession?) -> NowPlayingStore {
        let store = NowPlayingStore()
        store.apply(.session(session))
        if let cover {
            store.apply(.artwork(id: "cover", data: cover))
        }
        return store
    }

    @Test(arguments: [true, false])
    func figureWithCover(dark: Bool) {
        assertItem(store(track()), style: .figure, dark: dark, name: "figure-playing")
    }

    @Test(arguments: [true, false])
    func paused(dark: Bool) {
        let paused = store(track(playing: false))
        assertItem(paused, style: .figure, dark: dark, name: "figure-paused")
        assertItem(paused, style: .graph, dark: dark, name: "graph-paused")
        assertItem(paused, style: .graphAndFigure, dark: dark, name: "graph-figure-paused")
        assertItem(paused, style: .labelled, dark: dark, name: "labelled-paused")
    }

    @Test(arguments: [true, false])
    func nothingPlaying(dark: Bool) {
        assertItem(store(nil), style: .symbol, dark: dark, name: "symbol-idle")
    }
}

@MainActor
struct NowPlayingItemContentTests {
    private func store(_ session: NowPlayingSession?) -> NowPlayingStore {
        let store = NowPlayingStore()
        store.apply(.session(session))
        return store
    }

    @Test func titleAndArtist() {
        let content = ItemContent.nowPlaying(store(track()), options: [:])
        #expect(content.figure == "Northern Lights — Paper Satellites")
        #expect(content.detail == "Music")
        #expect(!content.isDimmed)
    }

    @Test func aPausedTrackFades() {
        let content = ItemContent.nowPlaying(store(track(playing: false)), options: [:])
        #expect(content.isDimmed)
        #expect(content.symbol == "pause.fill")
    }

    @Test func idleHidesUnlessTheUserKeepsIt() {
        #expect(ItemContent.nowPlaying(store(nil), options: [:]).isHidden)
        #expect(!ItemContent.nowPlaying(store(nil), options: [ModuleOption.hideWhenIdle: "false"]).isHidden)
    }

    @Test func aHiddenItemTakesNoRoom() {
        let monitor = SystemMonitor(nowPlaying: store(nil))
        #expect(MenuBarItemView.width(module: .nowPlaying, style: .figure, numbers: .compact, monitor: monitor) == 0)
    }

    @Test func longTextStopsAtTheLimit() throws {
        var long = track()
        long.track.title = String(repeating: "Very long title ", count: 20)
        let content = ItemContent.nowPlaying(store(long), options: [ModuleOption.maxWidth: "120"])
        #expect(content.figureWidth == 120)
        let short = ItemContent.nowPlaying(store(track()), options: [ModuleOption.maxWidth: "400"])
        #expect(try #require(short.figureWidth) < 400)
    }

    @Test func barsMoveOnlyWhilePlaying() {
        #expect(Set(ItemContent.equalizer(phase: nil)).count == 1)
        #expect(ItemContent.equalizer(phase: 3) != ItemContent.equalizer(phase: 4))
        #expect(ItemContent.equalizer(phase: 100_000).allSatisfy { (0 ... 1).contains($0) })
    }

    @Test func timesReadLikeAPlayer() {
        #expect(PlaybackTime.text(168) == "2:48")
        #expect(PlaybackTime.text(3768) == "1:02:48")
        #expect(PlaybackTime.remaining(72) == "−1:12")
        #expect(PlaybackTime.text(-3) == "0:00")
    }
}
