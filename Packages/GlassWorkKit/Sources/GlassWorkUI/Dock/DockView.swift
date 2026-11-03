import GlassWorkCore
import SwiftUI

/// What the Dock can ask the app to do.
@MainActor
public struct DockActions {
    public var open: (DockApp) -> Void
    public var showPanel: (ModuleID) -> Void
    public var update: (([DockItem]) -> [DockItem]) -> Void

    public init(
        open: @escaping (DockApp) -> Void,
        showPanel: @escaping (ModuleID) -> Void,
        update: @escaping (([DockItem]) -> [DockItem]) -> Void
    ) {
        self.open = open
        self.showPanel = showPanel
        self.update = update
    }
}

/// The Dock: apps, folders and live widgets on a glass bar.
public struct DockView: View {
    private let settings: DockSettings
    private let running: Set<String>
    private let monitor: SystemMonitor
    private let actions: DockActions
    @State private var pointerX: CGFloat?
    @State private var openFolder: AppFolder?

    public init(settings: DockSettings, running: Set<String>, monitor: SystemMonitor, actions: DockActions) {
        self.settings = settings
        self.running = running
        self.monitor = monitor
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 10) {
            if let openFolder {
                FolderCard(folder: openFolder, actions: actions) { self.openFolder = nil }
            }
            bar
        }
    }

    private var bar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(settings.items.enumerated()), id: \.element.id) { index, item in
                tile(item, size: size(at: index))
            }
        }
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .onContinuousHover { phase in
            switch phase {
            case let .active(location): pointerX = settings.magnifies ? location.x : nil
            case .ended: pointerX = nil
            }
        }
    }

    private func size(at index: Int) -> CGFloat {
        guard let pointerX else { return settings.iconSize }
        let center = 8 + (CGFloat(index) + 0.5) * (settings.iconSize + 8)
        return DockMagnification.size(
            distance: pointerX - center,
            base: settings.iconSize,
            magnified: settings.magnifiedSize
        )
    }

    @ViewBuilder
    private func tile(_ item: DockItem, size: CGFloat) -> some View {
        switch item {
        case let .app(app):
            AppTile(app: app, size: size, isRunning: running.contains(app.path)) { actions.open(app) }
        case let .folder(folder):
            FolderTile(folder: folder, size: size, isRunning: folder.apps.contains { running.contains($0.path) }) {
                openFolder = openFolder?.id == folder.id ? nil : folder
            }
        case let .widget(module):
            WidgetTile(module: module, size: size, monitor: monitor) { actions.showPanel(module) }
        }
    }
}

struct AppIcon: View {
    let app: DockApp
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct AppTile: View {
    let app: DockApp
    let size: CGFloat
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                AppIcon(app: app, size: size)
                Circle().fill(isRunning ? Color.primary : .clear).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .help(app.name)
    }
}

/// Glass square with a 3×3 grid of the folder's first apps.
struct FolderTile: View {
    let folder: AppFolder
    let size: CGFloat
    let isRunning: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                content
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: size / 4.5))
                Circle().fill(isRunning ? Color.primary : .clear).frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .help(folder.name)
    }

    @ViewBuilder
    private var content: some View {
        if let symbol = folder.symbol {
            Image(systemName: symbol).font(.system(size: size * 0.5))
        } else {
            let cell = size * 0.24
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell), spacing: 2), count: 3), spacing: 2) {
                ForEach(folder.apps.prefix(9)) { AppIcon(app: $0, size: cell) }
            }
        }
    }
}

/// The opened folder above the Dock.
struct FolderCard: View {
    let folder: AppFolder
    let actions: DockActions
    let close: () -> Void
    @State private var name: String
    @State private var query = ""

    init(folder: AppFolder, actions: DockActions, close: @escaping () -> Void) {
        self.folder = folder
        self.actions = actions
        self.close = close
        _name = State(initialValue: folder.name)
    }

    private var apps: [DockApp] {
        folder.sortedApps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField(loc("Folder name"), text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .onSubmit(rename)
                Menu {
                    Button(loc("Ungroup")) {
                        actions.update { DockLayout.ungroup(folder, in: $0) }
                        close()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if folder.apps.count > 12 {
                TextField(loc("Search"), text: $query).textFieldStyle(.roundedBorder)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 8), count: 5), spacing: 12) {
                    ForEach(apps) { app in
                        Button {
                            actions.open(app)
                            close()
                        } label: {
                            VStack(spacing: 4) {
                                AppIcon(app: app, size: 52)
                                Text(app.name).font(.system(size: 11)).lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(loc("Remove from Folder")) {
                                actions.update { DockLayout.remove(app, from: folder, in: $0) }
                                close()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(16)
        .frame(width: 430)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func rename() {
        actions.update { items in
            items.map { item in
                guard item == .folder(folder) else { return item }
                var renamed = folder
                renamed.name = name
                return .folder(renamed)
            }
        }
    }
}

/// Live mini view of a module. Click opens its card.
struct WidgetTile: View {
    let module: ModuleID
    let size: CGFloat
    let monitor: SystemMonitor
    let action: () -> Void

    var body: some View {
        let content = ItemContent.content(module, monitor: monitor, style: .compact)
        Button(action: action) {
            VStack(spacing: 3) {
                VStack(spacing: 1) {
                    Image(systemName: module.symbol).font(.system(size: size * 0.28)).foregroundStyle(module.tint)
                    Text(content.figure)
                        .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: size, height: size)
                .background(.black.opacity(0.28), in: .rect(cornerRadius: size / 4.5))
                Color.clear.frame(width: 4, height: 4)
            }
        }
        .buttonStyle(.plain)
        .help(module.title)
    }
}
