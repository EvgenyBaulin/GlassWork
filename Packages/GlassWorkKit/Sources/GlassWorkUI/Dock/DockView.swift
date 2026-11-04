import GlassWorkCore
import SwiftUI

/// What the Dock can ask the app to do.
@MainActor
public struct DockActions {
    public var open: (DockApp) -> Void
    public var showPanel: (ModuleID) -> Void
    public var update: (([DockItem]) -> [DockItem]) -> Void
    /// Tells the window what to make room for.
    public var needsSpace: (DockSpace) -> Void

    public init(
        open: @escaping (DockApp) -> Void,
        showPanel: @escaping (ModuleID) -> Void,
        update: @escaping (([DockItem]) -> [DockItem]) -> Void,
        needsSpace: @escaping (DockSpace) -> Void
    ) {
        self.open = open
        self.showPanel = showPanel
        self.update = update
        self.needsSpace = needsSpace
    }
}

/// The Dock: apps, folders and live widgets on a glass bar.
public struct DockView: View {
    private let state: DockLiveState
    private let monitor: SystemMonitor
    private let actions: DockActions
    /// Distance from the middle of the Dock, which stays put however wide the bar gets.
    @State private var pointer: Double?
    @State private var openFolderID: AppFolder.ID?

    private static let canvas = "dock"
    /// Quick enough to feel attached to the pointer, long enough not to pop.
    private static let hoverAnimation = Animation.easeOut(duration: 0.14)

    /// - Parameter pointer: Where the pointer starts, measured from the middle of the Dock.
    public init(state: DockLiveState, monitor: SystemMonitor, actions: DockActions, pointer: Double? = nil) {
        self.state = state
        self.monitor = monitor
        self.actions = actions
        _pointer = State(initialValue: pointer)
    }

    private var settings: DockSettings {
        state.settings
    }

    private var running: Set<String> {
        state.running
    }

    /// Read fresh from settings, so renaming a folder does not leave the card holding the old one.
    private var openFolder: AppFolder? {
        settings.items.lazy.compactMap { item -> AppFolder? in
            if case let .folder(folder) = item, folder.id == openFolderID {
                return folder
            }
            return nil
        }.first
    }

    private var space: DockSpace {
        if openFolder != nil {
            return .folder
        }
        return pointer == nil ? .rest : .magnified
    }

    /// Everything hangs from the bottom edge, so the window can change size without the bar moving.
    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let openFolder {
                    FolderCard(folder: openFolder, actions: actions) { openFolderID = nil }
                        .padding(.bottom, cardLift)
                }
                bar(middle: proxy.size.width / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .coordinateSpace(.named(Self.canvas))
        .onChange(of: space) { _, space in actions.needsSpace(space) }
    }

    private var cardLift: Double {
        DockBarLayout.restHeight(base: settings.iconSize) + DockBarLayout.growth(settings) + DockBarLayout.folderCardGap
    }

    private func bar(middle: Double) -> some View {
        let layout = DockBarLayout(
            count: settings.items.count,
            base: settings.iconSize,
            magnified: settings.magnifiedSize,
            pointer: settings.magnifies ? pointer : nil
        )
        return HStack(alignment: .bottom, spacing: DockBarLayout.spacing) {
            ForEach(Array(settings.items.enumerated()), id: \.element.id) { index, item in
                tile(item, size: layout.sizes[index])
            }
        }
        .padding(DockBarLayout.padding)
        .background(alignment: .bottom) {
            // Keeps its height: icons grow up and out of it.
            Color.clear
                .frame(height: DockBarLayout.restHeight(base: settings.iconSize))
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .onContinuousHover(coordinateSpace: .named(Self.canvas)) { phase in
            switch phase {
            case let .active(location): movePointer(to: location.x - middle)
            case .ended: movePointer(to: nil)
            }
        }
        .offset(x: layout.centerX)
    }

    /// Entering and leaving animate. Moving does not need to: sizes already change continuously.
    private func movePointer(to position: Double?) {
        let target = settings.magnifies ? position : nil
        if (target == nil) == (pointer == nil) {
            pointer = target
        } else {
            withAnimation(Self.hoverAnimation) { pointer = target }
        }
    }

    @ViewBuilder
    private func tile(_ item: DockItem, size: CGFloat) -> some View {
        switch item {
        case let .app(app):
            AppTile(
                app: app,
                size: size,
                isRunning: running.contains(app.path),
                isLaunching: state.launching.contains(app.path)
            ) { actions.open(app) }
                .draggable(app.path)
                .dropDestination(for: String.self) { paths, _ in
                    drop(paths) { dragged, items in DockLayout.drop(dragged, onto: app, in: items) }
                }
        case let .folder(folder):
            FolderTile(
                folder: folder,
                size: size,
                isRunning: folder.apps.contains { running.contains($0.path) },
                isLaunching: folder.apps.contains { state.launching.contains($0.path) }
            ) {
                openFolderID = openFolderID == folder.id ? nil : folder.id
            }
            .dropDestination(for: String.self) { paths, _ in
                drop(paths) { dragged, items in DockLayout.drop(dragged, into: folder, in: items) }
            }
        case let .widget(module):
            WidgetTile(module: module, size: size, monitor: monitor) { actions.showPanel(module) }
        }
    }
}

private extension DockView {
    /// Applies a drop of an app already in the Dock.
    func drop(_ paths: [String], change: @escaping (DockApp, [DockItem]) -> [DockItem]) -> Bool {
        guard let path = paths.first, let dragged = app(at: path) else { return false }
        actions.update { change(dragged, $0) }
        return true
    }

    func app(at path: String) -> DockApp? {
        settings.items.compactMap { item -> DockApp? in
            if case let .app(app) = item, app.path == path {
                return app
            }
            return nil
        }.first
    }
}

/// Sizes change on every pointer move, and asking the system for an icon each time is too slow.
@MainActor
private enum DockIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        if let icon = cache[path] {
            return icon
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}

struct AppIcon: View {
    let app: DockApp
    let size: CGFloat

    var body: some View {
        Image(nsImage: DockIcons.icon(for: app.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

/// Jumps until the app is up. Only draws higher, so nothing around the icon moves.
struct LaunchBounce: ViewModifier {
    let isActive: Bool
    let size: CGFloat
    /// A fixed height from 0 to 1 in place of the motion, for snapshots.
    var pose: Double?
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func body(content: Content) -> some View {
        let height = size * DockBarLayout.bounce
        let isStill = reducesMotion
        content.keyframeAnimator(initialValue: pose ?? 0, repeating: isActive && pose == nil) { view, lift in
            view
                .offset(y: isStill ? 0 : -height * lift)
                .opacity(isStill ? 1 - lift / 2 : 1)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.28)
                CubicKeyframe(0, duration: 0.28)
                LinearKeyframe(0, duration: 0.08)
            }
        }
    }
}

struct AppTile: View {
    let app: DockApp
    let size: CGFloat
    let isRunning: Bool
    var isLaunching = false
    var pose: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                AppIcon(app: app, size: size)
                    .modifier(LaunchBounce(isActive: isLaunching, size: size, pose: pose))
                Circle().fill(isRunning || isLaunching ? Color.primary : .clear).frame(width: 4, height: 4)
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
    var isLaunching = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                content
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: size / 4.5))
                    .modifier(LaunchBounce(isActive: isLaunching, size: size))
                Circle().fill(isRunning || isLaunching ? Color.primary : .clear).frame(width: 4, height: 4)
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
