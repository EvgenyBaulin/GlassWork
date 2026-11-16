import AppKit
import GlassWorkCore
import SwiftUI

struct IslandNowPlaying: View {
    let presentation: IslandPresentation
    let session: NowPlayingSession
    let actions: IslandActions

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ArtworkTile(data: presentation.event.context.artwork, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.track.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(presentation.subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Text([session.sourceName, presentation.event.context.outputDevice]
                        .compactMap(\.self).joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if session.isPlaying {
                    IslandLevelBars(tint: presentation.tint)
                }
            }
            PlaybackScrubber(session: session, now: presentation.now, seek: actions.seek)
            TransportRow(session: session, size: 18, spacing: 55)
                .environment(\.nowPlayingButton, NowPlayingButtonMaker(perform: actions.perform))
                .accessibilityElement(children: .contain)
        }
    }
}

struct IslandClipboardPreview: View {
    let entry: ClipboardEntry
    let data: Data?
    var imageURL: URL?
    let actions: IslandActions

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            preview
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color(white: 0.075), in: .rect(cornerRadius: 12))
                .clipShape(.rect(cornerRadius: 12))
            Text(caption).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 8) {
                IslandCapsule(title: entry.isPinned ? loc("Unpin") : loc("Pin")) { actions.pin(entry.id) }
                IslandCapsule(title: loc("History ⇧⌘V"), tint: Palette.teal, action: actions.openHistory)
            }
        }
        .task(id: imageURL) { thumbnail = await ClipboardIcon.load(imageURL, size: 760) }
    }

    @ViewBuilder
    private var preview: some View {
        switch entry.kind {
        case .image:
            if let data, let image = NSImage(data: data) {
                imagePreview(Image(nsImage: image))
            } else if let thumbnail {
                imagePreview(Image(decorative: thumbnail, scale: 1))
            } else {
                Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .accessibilityLabel(loc("Image"))
            }
        case .color:
            Color(hex: entry.text).overlay { Text(entry.text).font(.system(size: 16, design: .monospaced)) }
        case .link:
            Label(entry.text, systemImage: "link").font(.system(size: 13)).lineLimit(3).padding(12)
        case .file:
            Label(URL(fileURLWithPath: entry.text).lastPathComponent, systemImage: "doc")
                .font(.system(size: 13)).lineLimit(3).padding(12)
        case .text:
            Text(entry.text).font(.system(size: 13)).lineLimit(5).padding(12)
        }
    }

    private func imagePreview(_ image: Image) -> some View {
        GeometryReader { geometry in
            image.resizable().scaledToFill()
                .frame(width: geometry.size.width, height: 120).clipped()
        }
        .frame(height: 120)
    }

    private var caption: String {
        if let width = entry.pixelWidth, let height = entry.pixelHeight {
            return loc("\(width) × \(height) · \(Format.size(Double(entry.byteCount)))")
        }
        return Format.size(Double(entry.byteCount))
    }
}
