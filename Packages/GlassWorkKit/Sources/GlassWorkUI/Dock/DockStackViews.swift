import GlassWorkCore
import SwiftUI
import UniformTypeIdentifiers

/// A line between groups of tiles. It sits in the gap between two slots and takes no room of its own, so the
/// bar's layout and hover are the same with it or without it.
struct DockDivider: View {
    let position: DockPosition
    let length: CGFloat

    var body: some View {
        let gap = DockBarLayout.spacing / 2
        Rectangle()
            .fill(.primary.opacity(0.22))
            .frame(width: position.isVertical ? length * 0.8 : 1, height: position.isVertical ? 1 : length * 0.8)
            .offset(x: position.isVertical ? 0 : gap, y: position.isVertical ? gap : 0)
            .allowsHitTesting(false)
    }
}

/// The previous and next buttons of a Dock with more widgets than room. The next button also shows where you are.
struct DockPagerTile: View {
    enum Direction {
        case previous, next
    }

    let direction: Direction
    let size: CGFloat
    let arrangement: DockArrangement
    var position = DockPosition.bottom
    let action: () -> Void

    private static let mostDots = 5

    private var isLastPage: Bool {
        arrangement.page >= arrangement.pageCount - 1
    }

    private var symbol: String {
        switch (direction, position.isVertical) {
        case (.previous, false): "chevron.left"
        case (.next, false): "chevron.right"
        case (.previous, true): "chevron.up"
        case (.next, true): "chevron.down"
        }
    }

    private var title: String {
        switch direction {
        case .previous: loc("Previous set")
        case .next: loc("Next set: \(arrangement.hiddenWidgets) more widgets")
        }
    }

    var body: some View {
        Button(action: action) {
            DockIndicated(position: position, isLit: false) {
                VStack(spacing: size * 0.1) {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.22, weight: .semibold))
                        .frame(width: size * 0.5, height: size * 0.5)
                        .background(.primary.opacity(0.14), in: .circle)
                    if direction == .next {
                        dots
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .buttonStyle(.plain)
        .disabled(direction == .next && isLastPage)
        .help(title)
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(0 ..< min(arrangement.pageCount, Self.mostDots), id: \.self) { index in
                Circle()
                    .fill(.primary.opacity(index == arrangement.page ? 0.9 : 0.3))
                    .frame(width: 4, height: 4)
            }
        }
    }
}

/// A folder in the Dock. Downloads shows how far its files have come.
struct StackTile: View {
    let stack: DockStack
    let files: [DockFile]
    let size: CGFloat
    var position = DockPosition.bottom
    let action: () -> Void

    private var progress: Double? {
        stack.isDownloads ? DockFiles.overallProgress(files) : nil
    }

    private var title: String {
        progress.map { "\(stack.name) · \(Format.percent($0))" } ?? stack.name
    }

    var body: some View {
        Button(action: action) {
            DockIndicated(position: position, isLit: false) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: size / 4.5)
                        .fill(Palette.blue.gradient)
                    Image(systemName: stack.isDownloads ? "arrow.down.to.line" : "doc.on.doc.fill")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: size, height: size)
                    if let progress {
                        ThinBar(value: progress, tint: .white)
                            .padding(.horizontal, size * 0.14)
                            .padding(.bottom, size * 0.1)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// Right-click on a stack.
struct StackMenu: View {
    let stack: DockStack
    let actions: DockActions

    var body: some View {
        Button(loc("Open in Finder")) { actions.showFolder(stack.path) }
        if !stack.isDownloads {
            Menu(loc("Display as")) {
                ForEach(DockStackStyle.allCases, id: \.self) { style in
                    Toggle(style.title, isOn: Binding(
                        get: { stack.style == style },
                        set: { _ in actions.update { DockLayout.setting(style, of: stack, in: $0) } }
                    ))
                }
            }
        }
        Divider()
        Button(loc("Remove from Dock")) { actions.update { DockLayout.removing(.stack(stack), from: $0) } }
    }
}

public extension DockStackStyle {
    var title: String {
        switch self {
        case .fan: loc("Dock stack fan")
        case .grid: loc("Grid")
        }
    }
}

/// Icons come from the file's type and never from its path: asking for a file's own icon would read inside a
/// folder macOS may guard, and icons here must not depend on what is on the disk.
@MainActor
private enum DockFileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for file: DockFile) -> NSImage {
        let key = file.isFolder ? "/" : file.typeExtension
        if let icon = cache[key] {
            return icon
        }
        let type = file.isFolder ? UTType.folder : UTType(filenameExtension: key) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        cache[key] = icon
        return icon
    }
}

struct DockFileIcon: View {
    let file: DockFile
    let size: CGFloat

    var body: some View {
        Image(nsImage: DockFileIcons.icon(for: file))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// What opens above a stack's tile. As with panels, the host adds the glass: tinted glass drawn off screen hides
/// everything under it, and snapshots could not see the card.
struct StackCard: View {
    let stack: DockStack
    let files: [DockFile]
    var position = DockPosition.bottom
    let actions: DockActions
    var now = Date.now
    let close: () -> Void

    var body: some View {
        if stack.isDownloads {
            DownloadsCard(stack: stack, files: files, actions: actions, now: now, close: close)
        } else if stack.showsFan(at: position) {
            StackFan(stack: stack, files: files, actions: actions, close: close)
        } else {
            StackGrid(stack: stack, files: files, actions: actions, close: close)
        }
    }
}

/// The newest files in an arc, the newest nearest the Dock.
struct StackFan: View {
    let stack: DockStack
    let files: [DockFile]
    let actions: DockActions
    let close: () -> Void

    private var shown: [DockFile] {
        Array(files.prefix(DockFiles.fanLimit))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button(loc("Open in Finder")) {
                actions.showFolder(stack.path)
                close()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
            .offset(x: DockFan.offset(at: shown.count))
            ForEach(Array(shown.enumerated().reversed()), id: \.element.id) { index, file in
                row(file).offset(x: DockFan.offset(at: index))
            }
        }
    }

    private func row(_ file: DockFile) -> some View {
        Button {
            actions.openFile(file.path)
            close()
        } label: {
            HStack(spacing: 10) {
                // Stands straight on the wallpaper, so it is white in both themes, as in the design.
                Text(file.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.6), radius: 2)
                DockFileIcon(file: file, size: 48)
            }
        }
        .buttonStyle(.plain)
        .draggable(URL(filePath: file.path))
    }
}

/// A stack's files on a glass card, four to a row.
struct StackGrid: View {
    let stack: DockStack
    let files: [DockFile]
    let actions: DockActions
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(stack.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(loc("Open in Finder")) {
                    actions.showFolder(stack.path)
                    close()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.blue)
            }
            if files.isEmpty {
                WidgetEmptyState(symbol: "folder", title: loc("This folder is empty")).frame(height: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 8), count: 4), spacing: 14) {
                        ForEach(files) { cell($0) }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func cell(_ file: DockFile) -> some View {
        Button {
            actions.openFile(file.path)
            close()
        } label: {
            VStack(spacing: 4) {
                DockFileIcon(file: file, size: 52)
                Text(file.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
            }
        }
        .buttonStyle(.plain)
        .draggable(URL(filePath: file.path))
    }
}

/// Downloads, newest first, with search, progress, and files that can be dragged out.
struct DownloadsCard: View {
    let stack: DockStack
    let files: [DockFile]
    let actions: DockActions
    var now = Date.now
    let close: () -> Void
    @State private var query = ""

    private var shown: [DockFile] {
        DockFiles.matching(files, query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stack.name).font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(loc("Newest first")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if files.isEmpty {
                WidgetEmptyState(
                    symbol: "arrow.down.to.line",
                    title: loc("No downloads yet"),
                    detail: loc("Files you download appear here, newest first.")
                )
                .frame(height: 150)
            } else {
                TextField(loc("Search downloads"), text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(shown) { row($0) }
                    }
                }
                .frame(maxHeight: 280)
                Button(loc("Open in Finder")) {
                    actions.showFolder(stack.path)
                    close()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.blue)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    @ViewBuilder
    private func row(_ file: DockFile) -> some View {
        if file.isDownloading {
            content(file)
        } else {
            Button {
                actions.openFile(file.path)
                close()
            } label: {
                content(file)
            }
            .buttonStyle(.plain)
            .draggable(URL(filePath: file.path))
        }
    }

    private func content(_ file: DockFile) -> some View {
        HStack(spacing: 10) {
            DockFileIcon(file: file, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                Text(detail(file)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if file.isDownloading {
                    ThinBar(value: file.progress ?? 0, tint: Palette.blue)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    private func detail(_ file: DockFile) -> String {
        guard file.isDownloading else {
            let age = RelativeDateTimeFormatter().localizedString(for: file.added, relativeTo: now)
            return file.isFolder ? age : "\(Format.bytes(Double(file.size), style: .precise)) · \(age)"
        }
        return file.progress.map { loc("Downloading: \(Format.percent($0))") } ?? loc("Downloading…")
    }
}
