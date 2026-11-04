import GlassWorkCore
import SwiftUI

/// The current track with its cover, a seek bar and transport controls.
struct NowPlayingPanel: View {
    let store: NowPlayingStore
    /// Set by tests to freeze the clock.
    var fixedNow: Date?
    @Environment(\.panelActions) private var actions

    var body: some View {
        PanelFrame(
            module: .nowPlaying,
            subtitle: store.session?.sourceName ?? "",
            footerTitle: footerTitle,
            footerAction: footerAction
        ) {
            if let session = store.session {
                track(session).environment(\.nowPlayingButton, NowPlayingButtonMaker { command in
                    store.perform(command)
                })
            } else {
                empty
            }
        }
    }

    private var footerTitle: String? {
        store.session?.sourceName.map { loc("Open \($0)") }
    }

    private var footerAction: (() -> Void)? {
        guard let id = store.session?.bundleID else { return nil }
        return { actions.openApp(id) }
    }

    private func track(_ session: NowPlayingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ArtworkTile(data: store.artwork, size: 76)
                TrackLabels(track: session.track, titleSize: 15, titleLines: 2)
                Spacer(minLength: 0)
            }
            progress(session)
            TransportRow(session: session, size: 16, spacing: 22)
        }
    }

    /// Ticks only while the track plays and the panel is open.
    @ViewBuilder
    private func progress(_ session: NowPlayingSession) -> some View {
        if let fixedNow {
            PlaybackScrubber(session: session, now: fixedNow, seek: seek)
        } else if session.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                PlaybackScrubber(session: session, now: context.date, seek: seek)
            }
        } else {
            PlaybackScrubber(session: session, now: Date(), seek: seek)
        }
    }

    private func seek(_ position: TimeInterval) {
        store.perform(.seek(position))
    }

    @ViewBuilder
    private var empty: some View {
        if store.hasLoaded {
            VStack(spacing: 8) {
                Image(systemName: "music.note")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(store.isUnavailable ? loc("macOS did not answer") : loc("Nothing playing"))
                    .font(.system(size: 14, weight: .semibold))
                Text(store.isUnavailable
                    ? loc("This version of macOS does not let GlassWork see what is playing.")
                    : loc("Start music or a podcast in any app."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }
}

/// The track position: hovering reads a time, and clicking or dragging moves there when the player allows it.
struct PlaybackScrubber: View {
    let session: NowPlayingSession
    let now: Date
    let seek: (TimeInterval) -> Void
    @State private var hover: Double?
    @State private var dragged: Double?

    /// `initialHover` starts it as if the cursor were there, for tests of the hover state.
    init(
        session: NowPlayingSession,
        now: Date,
        initialHover: Double? = nil,
        seek: @escaping (TimeInterval) -> Void
    ) {
        self.session = session
        self.now = now
        self.seek = seek
        _hover = State(initialValue: initialHover)
    }

    var body: some View {
        if let duration = session.track.duration {
            VStack(spacing: 4) {
                track(duration).frame(height: 14)
                HStack {
                    Text(PlaybackTime.text(shownPosition(duration)))
                    Spacer()
                    Text(PlaybackTime.remaining(duration - shownPosition(duration)))
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    private func shownPosition(_ duration: TimeInterval) -> TimeInterval {
        dragged.map { $0 * duration } ?? session.position(at: now)
    }

    private func track(_ duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            let share = shownPosition(duration) / duration
            let isActive = hover != nil || dragged != nil
            ZStack(alignment: .leading) {
                ThinBar(value: share, tint: Palette.pink)
                if session.canSeek {
                    Circle()
                        .fill(.white)
                        .shadow(radius: 1)
                        .frame(width: 10, height: 10)
                        .offset(x: geometry.size.width * share - 5)
                        .opacity(isActive || session.isPlaying ? 1 : 0.6)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): hover = fraction(point.x, geometry)
                case .ended: hover = nil
                }
            }
            .gesture(drag(duration, geometry))
            .overlay(alignment: .topLeading) { readout(duration, geometry) }
            .animation(.easeOut(duration: 0.15), value: hover == nil)
        }
    }

    private func fraction(_ x: CGFloat, _ geometry: GeometryProxy) -> Double {
        min(max(x / max(geometry.size.width, 1), 0), 1)
    }

    private func drag(_ duration: TimeInterval, _ geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if session.canSeek {
                    dragged = fraction(value.location.x, geometry)
                }
            }
            .onEnded { value in
                guard session.canSeek else { return }
                dragged = nil
                seek(fraction(value.location.x, geometry) * duration)
            }
    }

    @ViewBuilder
    private func readout(_ duration: TimeInterval, _ geometry: GeometryProxy) -> some View {
        if let hover {
            let row = ChartTooltip.Row(
                id: "position",
                title: loc("Position"),
                value: PlaybackTime.text(hover * duration),
                color: Palette.pink
            )
            ChartTooltip(rows: [row])
                .fixedSize()
                .offset(x: min(max(geometry.size.width * hover - 50, 0), max(geometry.size.width - 110, 0)), y: -32)
                .allowsHitTesting(false)
        }
    }
}
