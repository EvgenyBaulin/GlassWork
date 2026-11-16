import AppKit
import GlassWorkCore
import SwiftUI

/// The shelf: drop files on it, drag them out later.
struct ShelfPanel: View {
    let store: ShelfStore
    @Environment(\.panelActions) private var actions
    @State private var isTargeted = false
    @State private var isConfirmingClear = false

    var body: some View {
        PanelFrame(
            module: .shelf,
            subtitle: subtitle,
            footerTitle: store.items.isEmpty ? nil : loc("Clear all"),
            footerAction: { isConfirmingClear = true }
        ) {
            if store.items.isEmpty {
                emptyZone
            } else {
                grid
                dropHint
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await store.add(files) }
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .confirmationDialog(loc("Clear the shelf?"), isPresented: $isConfirmingClear) {
            Button(loc("Clear all"), role: .destructive) { store.clearAll() }
        } message: {
            Text(loc("Files stay where they are unless the shelf copied them."))
        }
        .onAppear { store.refresh() }
    }

    private var subtitle: String {
        guard !store.items.isEmpty else { return "" }
        let count = store.items.count == 1 ? loc("1 file") : loc("\(store.items.count) files")
        return "\(count) · \(Format.bytes(Double(store.totalBytes), style: .precise))"
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isTargeted ? Palette.purple : Color.secondary.opacity(0.5),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
    }

    private var emptyZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(loc("Drop files here")).font(.system(size: 13, weight: .semibold))
            Text(loc("Keep them for later, then drag them out"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .background(isTargeted ? Palette.purple.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
        .overlay { border }
    }

    private var dropHint: some View {
        Text(loc("Drop files here to keep them for later"))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isTargeted ? Palette.purple.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
            .overlay { border }
    }

    /// Up to two rows take the room they need; more scroll, so the panel stays a sensible height.
    @ViewBuilder
    private var grid: some View {
        if store.items.count > 8 {
            ScrollView { tiles }.frame(height: 220)
        } else {
            tiles
        }
    }

    private var tiles: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: 4),
            spacing: 10
        ) {
            ForEach(store.items) { item in
                ShelfTile(item: item, showsThumbnail: store.settings.showsThumbnails) {
                    actions.openURL(item.url)
                } onReveal: {
                    actions.showInFinder(item.path)
                } onRemove: {
                    store.remove(item)
                }
            }
        }
    }
}

/// One file: its icon above its name. Drag it out to use it, click to open it.
struct ShelfTile: View {
    let item: ShelfItem
    var showsThumbnail = true
    var isHovered = false
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false
    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: 56, height: 56)
                .overlay(alignment: .topTrailing) {
                    if hovering || isHovered {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical)
                        }
                        .buttonStyle(.plain)
                        .help(loc("Remove"))
                        .offset(x: 4, y: -4)
                    }
                }
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .background(hovering || isHovered ? .white.opacity(0.08) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.name)
        .contextMenu {
            Button(loc("Open file"), action: onOpen)
            Button(loc("Show in Finder"), action: onReveal)
            Divider()
            Button(loc("Remove"), action: onRemove)
        }
        .task(id: item.path) {
            thumbnail = showsThumbnail && item.kind == .image ? await ClipboardIcon.load(item.url, size: 112) : nil
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
                .clipShape(.rect(cornerRadius: 10))
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.path)).resizable().scaledToFit()
        }
    }
}
