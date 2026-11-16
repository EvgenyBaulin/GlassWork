import GlassWorkCore
import Quartz
import SwiftUI

/// Resting the pointer on a file in a stack shows what is in it; on a folder, what the folder holds.
struct DockFilePreview: ViewModifier {
    let file: DockFile
    var edge = Edge.trailing
    @State private var isHovered = false
    @State private var isShown = false

    /// Long enough that moving along the list does not open one preview after another.
    private static let delay = Duration.milliseconds(600)

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .task(id: isHovered) {
                guard isHovered else {
                    isShown = false
                    return
                }
                try? await Task.sleep(for: Self.delay)
                if !Task.isCancelled, isHovered, !file.isDownloading {
                    isShown = true
                }
            }
            .popover(isPresented: $isShown, arrowEdge: edge) {
                DockFilePreviewCard(file: file)
            }
    }
}

private struct DockFilePreviewCard: View {
    let file: DockFile
    @State private var folder: FolderSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if file.isFolder {
                HStack(spacing: 10) {
                    DockFileIcon(file: file, size: 48)
                    Text(file.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                }
                if let folder {
                    fact(loc("Items"), "\(folder.count)")
                    fact(
                        loc("Size"),
                        Format.bytes(Double(folder.bytes), style: .precise) + (folder.isPartial ? "+" : "")
                    )
                }
            } else {
                QuickLookView(url: URL(filePath: file.path))
                    .frame(width: 300, height: 220)
                    .clipShape(.rect(cornerRadius: 8))
                Text(file.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                fact(loc("Size"), Format.bytes(Double(file.size), style: .precise))
            }
            fact(loc("Added"), file.added.formatted(date: .abbreviated, time: .shortened))
        }
        .padding(12)
        .frame(width: file.isFolder ? 240 : 324, alignment: .leading)
        .task {
            if file.isFolder {
                let path = file.path
                folder = await Task.detached { FolderSummary(path: path) }.value
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// What a folder holds, one level down. A large folder is counted only so far.
struct FolderSummary: Sendable, Equatable {
    var count = 0
    var bytes: Int64 = 0
    /// More entries than were looked at.
    var isPartial = false

    static let limit = 2000

    init(count: Int, bytes: Int64, isPartial: Bool) {
        self.count = count
        self.bytes = bytes
        self.isPartial = isPartial
    }

    init(path: String) {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        count = items.count
        isPartial = items.count > Self.limit
        for item in items.prefix(Self.limit) {
            bytes += Int64((try? item.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0)
        }
    }
}

/// The system's Quick Look preview of a file.
private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context _: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context _: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator _: ()) {
        view.close()
    }
}
