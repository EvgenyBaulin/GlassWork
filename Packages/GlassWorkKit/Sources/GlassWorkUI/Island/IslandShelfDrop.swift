import GlassWorkCore
import SwiftUI

/// The card the island opens while files are dragged over the notch.
struct IslandShelfDropZone: View {
    let preview: IslandDropPreview

    /// The card's height, so the host can size the island before drawing it.
    static let height: CGFloat = 162

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            zone
        }
        .frame(height: Self.height, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Palette.purple, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc("Drop to park on the Shelf")).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(alreadyThere).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var zone: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc").font(.system(size: 22, weight: .light))
            Text(releaseText).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(preview.listedNames)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.purple.opacity(0.12), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Palette.purple.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    var releaseText: String {
        preview.count == 1 ? loc("Release to add 1 file") : loc("Release to add \(preview.count) files")
    }

    var alreadyThere: String {
        switch preview.onShelf {
        case 0: loc("The Shelf is empty")
        case 1: loc("1 item already there")
        default: loc("\(preview.onShelf) items already there")
        }
    }
}
