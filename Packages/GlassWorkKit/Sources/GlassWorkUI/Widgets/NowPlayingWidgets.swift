import GlassWorkCore
import SwiftUI

private let musicURL = URL(string: "music://")

/// Cover, track, progress and controls. S shows the track, each size up adds to it.
struct NowPlayingWidget: View {
    let size: WidgetSize
    let data: NowPlayingWidgetData?
    let now: Date
    /// True in WidgetKit, where the system moves the progress.
    let isSystemTimed: Bool
    @Environment(\.nowPlayingButton) private var maker

    var body: some View {
        if let data {
            switch size {
            case .small: small(data)
            case .medium: medium(data)
            case .large: large(data)
            case .extraLarge: extraLarge(data)
            }
        } else {
            NotPlayingFace(size: size)
        }
    }

    private func small(_ data: NowPlayingWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ArtworkTile(data: data.artwork, size: 78)
                Spacer()
                ModuleIcon(.nowPlaying, size: 20)
            }
            Spacer(minLength: 6)
            TrackLabels(track: data.session.track, titleSize: 13, showsAlbum: false)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed, showsTimes: false)
                Spacer(minLength: 0)
                maker.button(.toggle, label: TransportGlyph(
                    symbol: data.session.isPlaying ? "pause.fill" : "play.fill",
                    size: 12
                ))
            }
        }
    }

    private func medium(_ data: NowPlayingWidgetData) -> some View {
        HStack(spacing: 14) {
            ArtworkTile(data: data.artwork, size: 138)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    TrackLabels(track: data.session.track)
                    Spacer(minLength: 4)
                    ModuleIcon(.nowPlaying, size: 20)
                }
                Spacer(minLength: 4)
                PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed)
                TransportRow(session: data.session, size: 14, spacing: 14).padding(.top, 4)
            }
        }
    }

    private func large(_ data: NowPlayingWidgetData) -> some View {
        let hasQueue = !data.session.queue.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            MediaHeader(title: loc("Now Playing"), source: data.session.sourceName)
            HStack(spacing: 14) {
                ArtworkTile(data: data.artwork, size: hasQueue ? 96 : 150)
                TrackLabels(track: data.session.track, titleSize: 17, titleLines: 2)
                Spacer(minLength: 0)
            }
            PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed)
            TransportRow(session: data.session)
            if hasQueue {
                Divider()
                Text(loc("Up Next").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(data.session.queue.prefix(3).enumerated()), id: \.offset) { _, track in
                    QueueRow(track: track)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func extraLarge(_ data: NowPlayingWidgetData) -> some View {
        HStack(spacing: 18) {
            player(data).frame(maxWidth: .infinity)
            Divider()
            queue(data).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func player(_ data: NowPlayingWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MediaHeader(title: loc("Now Playing"))
            HStack(alignment: .top, spacing: 14) {
                ArtworkTile(data: data.artwork, size: 180)
                VStack(alignment: .leading, spacing: 0) {
                    TrackLabels(track: data.session.track, titleSize: 20, titleLines: 3)
                    Spacer(minLength: 4)
                    if let source = data.session.sourceName {
                        HStack(spacing: 6) {
                            ModuleIcon(.nowPlaying, size: 18)
                            Text(source).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .frame(height: 180, alignment: .topLeading)
            }
            PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed)
            TransportRow(session: data.session)
            Spacer(minLength: 0)
            if let device = data.outputDevice {
                Label(device, systemImage: "hifispeaker")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func queue(_ data: NowPlayingWidgetData) -> some View {
        let tracks = data.session.queue.prefix(6)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("Up Next").uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !tracks.isEmpty {
                    Text(summary(tracks)).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
            if tracks.isEmpty {
                Spacer()
                Text(emptyQueue(data))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                    QueueRow(track: track)
                }
                Spacer(minLength: 0)
            }
            if let album = data.session.track.album {
                Text(loc("Playing from \(album)")).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private func summary(_ tracks: ArraySlice<NowPlayingTrack>) -> String {
        let minutes = Int(tracks.compactMap(\.duration).reduce(0, +) / 60)
        let count = tracks.count
        return minutes > 0 ? "\(loc("\(count) songs")) · \(loc("\(minutes) min"))" : loc("\(count) songs")
    }

    private func emptyQueue(_ data: NowPlayingWidgetData) -> String {
        guard let source = data.session.sourceName else { return loc("This player does not share its queue.") }
        return loc("\(source) does not share its queue.")
    }
}

/// Shown when no app is playing. A click opens Music.
private struct NotPlayingFace: View {
    let size: WidgetSize

    var body: some View {
        switch size {
        case .small:
            optionalLink {
                VStack(alignment: .leading, spacing: 0) {
                    ArtworkTile(data: nil, size: 78)
                    Spacer(minLength: 6)
                    Text(loc("Not playing")).font(.system(size: 13, weight: .semibold))
                    Text(loc("Click to open Music")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        case .medium, .large, .extraLarge:
            HStack(spacing: 14) {
                ArtworkTile(data: nil, size: 138)
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("Not playing")).font(.system(size: 15, weight: .semibold))
                    Text(loc("Start something in Music, Spotify or any player and it shows up here."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    optionalLink {
                        Text(loc("Open Music"))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: size == .medium ? .top : .center)
        }
    }

    @ViewBuilder
    private func optionalLink(@ViewBuilder _ label: () -> some View) -> some View {
        if let musicURL {
            Link(destination: musicURL, label: label).buttonStyle(.plain)
        } else {
            label()
        }
    }
}

/// The current line of a song. The players that share lyrics give no timing, so the line is an estimate.
struct LyricsWidget: View {
    let size: WidgetSize
    let data: NowPlayingWidgetData?
    let now: Date
    let isSystemTimed: Bool

    var body: some View {
        if let data {
            if data.session.lyrics.isEmpty {
                NoLyricsFace(size: size, data: data)
            } else {
                lyrics(data)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                MediaHeader(title: loc("Lyrics"), symbol: "quote.bubble")
                Spacer()
                Text(loc("Not playing")).font(.system(size: 15, weight: .semibold))
                Text(loc("Lyrics appear here when the player shares them."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func current(_ data: NowPlayingWidgetData) -> Int {
        let progress = data.session.progress(at: now) ?? 0
        return LyricsTiming.lineIndex(in: data.session.lyrics, progress: progress) ?? 0
    }

    @ViewBuilder
    private func lyrics(_ data: NowPlayingWidgetData) -> some View {
        switch size {
        case .small: small(data)
        case .medium: medium(data)
        case .large: large(data)
        case .extraLarge: extraLarge(data)
        }
    }

    private func small(_ data: NowPlayingWidgetData) -> some View {
        let lines = data.session.lyrics
        let index = current(data)
        return VStack(alignment: .leading, spacing: 6) {
            MediaHeader(title: loc("Lyrics"), symbol: "quote.bubble")
            Text(lines[index]).font(.system(size: 17, weight: .bold)).lineLimit(3)
            if index + 1 < lines.count {
                Text(lines[index + 1]).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            Text(data.session.track.title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func medium(_ data: NowPlayingWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            trackHeader(data)
            Spacer(minLength: 0)
            LyricLines(
                lines: data.session.lyrics,
                current: current(data),
                before: 1,
                after: 1,
                size: 13,
                currentSize: 16
            )
            Spacer(minLength: 0)
            PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed, showsTimes: false)
        }
    }

    private func large(_ data: NowPlayingWidgetData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            trackHeader(data)
            Spacer(minLength: 0)
            LyricLines(
                lines: data.session.lyrics,
                current: current(data),
                before: 2,
                after: 4,
                size: 14,
                currentSize: 18
            )
            Spacer(minLength: 0)
            PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed)
        }
    }

    private func extraLarge(_ data: NowPlayingWidgetData) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                MediaHeader(title: loc("Lyrics"), symbol: "quote.bubble")
                HStack(alignment: .top, spacing: 14) {
                    ArtworkTile(data: data.artwork, size: 150)
                    TrackLabels(track: data.session.track, titleSize: 17, titleLines: 3)
                }
                PlaybackBar(session: data.session, now: now, isSystemTimed: isSystemTimed)
                TransportRow(session: data.session)
                Spacer(minLength: 0)
                Text(loc("Lyrics from the player")).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                LyricLines(
                    lines: data.session.lyrics,
                    current: current(data),
                    before: 2,
                    after: 5,
                    size: 15,
                    currentSize: 19
                )
                Spacer(minLength: 0)
                Text(loc("Line follows playback (estimated)")).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trackHeader(_ data: NowPlayingWidgetData) -> some View {
        HStack(spacing: 10) {
            ArtworkTile(data: data.artwork, size: 30, radius: 6)
            TrackLabels(track: data.session.track, titleSize: 13, showsAlbum: false)
            Spacer(minLength: 4)
            Image(systemName: "quote.bubble").font(.system(size: 12)).foregroundStyle(Palette.pink)
        }
    }
}

/// The lines around the current one, which stands out with a pink mark.
private struct LyricLines: View {
    let lines: [String]
    let current: Int
    let before: Int
    let after: Int
    let size: CGFloat
    let currentSize: CGFloat

    var body: some View {
        let first = max(current - before, 0)
        let last = min(current + after, lines.count - 1)
        VStack(alignment: .leading, spacing: size * 0.65) {
            ForEach(first ... last, id: \.self) { index in
                if index == current {
                    HStack(spacing: 7) {
                        Capsule().fill(Palette.pink).frame(width: 3, height: currentSize + 4)
                        Text(lines[index]).font(.system(size: currentSize, weight: .bold)).lineLimit(2)
                    }
                } else {
                    Text(lines[index])
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(index < current ? .tertiary : .secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct NoLyricsFace: View {
    let size: WidgetSize
    let data: NowPlayingWidgetData

    var body: some View {
        if size == .small {
            VStack(alignment: .leading, spacing: 4) {
                MediaHeader(title: loc("Lyrics"), symbol: "quote.bubble")
                Spacer(minLength: 0)
                Image(systemName: "quote.closing").font(.system(size: 22)).foregroundStyle(.tertiary)
                Text(loc("No lyrics")).font(.system(size: 15, weight: .semibold))
                Text(loc("for \(data.session.track.title)"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ArtworkTile(data: data.artwork, size: 30, radius: 6)
                    TrackLabels(track: data.session.track, titleSize: 13, showsAlbum: false)
                    Spacer(minLength: 4)
                }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "quote.closing").font(.system(size: 26)).foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc("No lyrics for this song")).font(.system(size: 15, weight: .semibold))
                        Text(loc("Lyrics appear here when the player shares them."))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
