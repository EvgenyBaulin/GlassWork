import AppKit
import GlassWorkCore
import SwiftUI

/// The shelf as a card of the Dock: the files, a place to drop more, and what can be done with them.
struct DockShelfCard: View {
    let store: ShelfStore
    @Environment(\.panelActions) private var actions
    @State private var isTargeted = false

    static let width = 340.0
    /// More files than this scroll, so the card stays a sensible height.
    private static let visibleRows = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            rows
            dropZone
            footer
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .dropDestination(for: URL.self) { urls, _ in ShelfDrop.add(urls, to: store) } isTargeted: { isTargeted = $0 }
        .onAppear { store.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ModuleIcon(.shelf, size: 24)
            Text(ModuleID.shelf.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.blue)
            Spacer()
        }
    }

    @ViewBuilder
    private var rows: some View {
        if store.items.count > Self.visibleRows {
            ScrollView { list }.frame(height: Double(Self.visibleRows) * DockShelfRow.height)
        } else {
            list
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.items) { item in
                DockShelfRow(item: item) {
                    actions.openURL(item.url)
                } onReveal: {
                    actions.showInFinder(item.path)
                } onRemove: {
                    store.remove(item)
                }
            }
        }
    }

    private var dropZone: some View {
        Text(loc("Drop files here"))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isTargeted ? Palette.purple.opacity(0.14) : .clear, in: .rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isTargeted ? Palette.purple : Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(loc("Drag items out"))
            Text("·")
            Button(loc("AirDrop")) { ShelfDrop.airDrop(store.items.map(\.url)) }
                .disabled(store.items.isEmpty)
            Text("·")
            Button(loc("Clear")) { store.clearAll() }
                .disabled(store.items.isEmpty)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }
}

/// One file of the card: a glyph, its name and its size. Drag it out to use it, click to open it.
struct DockShelfRow: View {
    let item: ShelfItem
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    static let height = 36.0

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(item.kind))
                .font(.system(size: 17))
                .frame(width: 24)
            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Format.size(Double(item.byteCount)))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .frame(height: Self.height)
        .background(hovering ? .white.opacity(0.08) : .clear, in: .rect(cornerRadius: 8))
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
    }

    static func symbol(_ kind: ShelfKind) -> String {
        switch kind {
        case .image: "photo"
        case .folder: "folder"
        case .archive: "doc.zipper"
        case .document, .other: "doc"
        }
    }
}

/// What the Dock does with files and the shelf.
@MainActor
enum ShelfDrop {
    /// Puts dropped files on the shelf; false when the drop held no files.
    static func add(_ urls: [URL], to store: ShelfStore) -> Bool {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return false }
        Task { await store.add(files) }
        return true
    }

    static func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls)
        else { return }
        service.perform(withItems: urls)
    }
}

/// The card a Dock widget opens: its panel, except where the Dock has a shape of its own.
public struct DockWidgetCard: View {
    private let module: ModuleID
    private let monitor: SystemMonitor

    public init(module: ModuleID, monitor: SystemMonitor) {
        self.module = module
        self.monitor = monitor
    }

    public var body: some View {
        if module == .shelf {
            DockShelfCard(store: monitor.shelf)
        } else {
            ModulePanel(module: module, monitor: monitor)
        }
    }
}
