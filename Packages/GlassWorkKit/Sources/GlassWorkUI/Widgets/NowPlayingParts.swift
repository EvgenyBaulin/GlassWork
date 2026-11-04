import AppKit
import GlassWorkCore
import SwiftUI

/// How a transport button acts. WidgetKit needs an App Intent, the app calls the store directly,
/// and the intent type has to live in the extension, so the host supplies the button.
@MainActor
public struct NowPlayingButtonMaker {
    private let make: @MainActor (NowPlayingCommand, AnyView) -> AnyView

    public init(make: @escaping @MainActor (NowPlayingCommand, AnyView) -> AnyView) {
        self.make = make
    }

    /// Uses a plain SwiftUI button with an action.
    public init(perform: @escaping @MainActor (NowPlayingCommand) -> Void) {
        make = { command, label in
            AnyView(Button { perform(command) } label: { label }.buttonStyle(.plain))
        }
    }

    func button(_ command: NowPlayingCommand, label: some View) -> AnyView {
        make(command, AnyView(label))
    }
}

public extension EnvironmentValues {
    @Entry var nowPlayingButton: NowPlayingButtonMaker = MainActor.assumeIsolated {
        NowPlayingButtonMaker(perform: { _ in })
    }
}

/// `2:48`, or `1:02:48` for anything an hour long.
enum PlaybackTime {
    static func text(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }

    static func remaining(_ seconds: TimeInterval) -> String {
        "−\(text(seconds))"
    }
}

/// Square cover, or a soft placeholder for tracks without one.
struct ArtworkTile: View {
    let data: Data?
    let size: CGFloat
    var radius: CGFloat?

    var body: some View {
        let corner = radius ?? size * 0.14
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: corner))
    }
}

/// Back, play or pause, and forward. Buttons the player does not offer are dimmed.
struct TransportRow: View {
    let session: NowPlayingSession
    var size: CGFloat = 18
    var spacing: CGFloat = 28
    @Environment(\.nowPlayingButton) private var maker

    var body: some View {
        HStack(spacing: spacing) {
            skip(.previous, symbol: "backward.fill", isEnabled: session.canGoPrevious)
            maker.button(.toggle, label: TransportGlyph(
                symbol: session.isPlaying ? "pause.fill" : "play.fill",
                size: size * 1.35
            ))
            skip(.next, symbol: "forward.fill", isEnabled: session.canGoNext)
        }
        .frame(maxWidth: .infinity)
    }

    private func skip(_ command: NowPlayingCommand, symbol: String, isEnabled: Bool) -> some View {
        maker.button(command, label: TransportGlyph(symbol: symbol, size: size))
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.35)
    }
}

struct TransportGlyph: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: size * 1.6, height: size * 1.6)
            .contentShape(.rect)
    }
}

/// The bar and both times. WidgetKit cannot refresh by the second, so there the system moves them.
struct PlaybackBar: View {
    let session: NowPlayingSession
    let now: Date
    /// True in WidgetKit.
    var isSystemTimed = false
    var showsTimes = true

    private var liveRange: ClosedRange<Date>? {
        guard isSystemTimed, let end = session.endDate(from: now), end > now else { return nil }
        let start = now.addingTimeInterval(-session.position(at: now))
        return start ... end
    }

    var body: some View {
        if let duration = session.track.duration {
            VStack(spacing: 4) {
                bar(duration)
                if showsTimes {
                    times(duration)
                }
            }
        }
    }

    @ViewBuilder
    private func bar(_ duration: TimeInterval) -> some View {
        if let range = liveRange {
            ProgressView(
                timerInterval: range,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .tint(Palette.pink)
            .labelsHidden()
        } else {
            ThinBar(value: session.position(at: now) / duration, tint: Palette.pink)
        }
    }

    private func times(_ duration: TimeInterval) -> some View {
        HStack {
            if let range = liveRange {
                Text(timerInterval: range, countsDown: false)
                Spacer()
                Text(timerInterval: now ... range.upperBound, countsDown: true)
                    .multilineTextAlignment(.trailing)
            } else {
                Text(PlaybackTime.text(session.position(at: now)))
                Spacer()
                Text(PlaybackTime.remaining(duration - session.position(at: now)))
            }
        }
        .font(.system(size: 11, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}

/// `NOW PLAYING` on the left and the player on the right.
struct MediaHeader: View {
    let title: String
    var symbol = "music.note"
    var source: String?

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title.uppercased())
            Spacer()
            if let source {
                Text(source).font(.system(size: 11)).foregroundStyle(Color.secondary).lineLimit(1)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Palette.pink)
    }
}

/// Title, artist and album stacked, with sizes from the widget that holds them.
struct TrackLabels: View {
    let track: NowPlayingTrack
    var titleSize: CGFloat = 15
    var titleLines = 1
    var showsAlbum = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: titleSize, weight: .semibold))
                .lineLimit(titleLines)
            if let artist = track.artist {
                Text(artist).font(.system(size: titleSize * 0.8)).foregroundStyle(.secondary).lineLimit(1)
            }
            if showsAlbum, let album = track.album {
                Text(album).font(.system(size: titleSize * 0.72)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

/// One song in the Up Next list.
struct QueueRow: View {
    let track: NowPlayingTrack

    var body: some View {
        HStack(spacing: 10) {
            ArtworkTile(data: nil, size: 30, radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let artist = track.artist {
                    Text(artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let duration = track.duration {
                Text(PlaybackTime.text(duration))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
