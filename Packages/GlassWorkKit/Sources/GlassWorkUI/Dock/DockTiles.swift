import GlassWorkCore
import SwiftUI

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

/// An icon with its running dot, on the side of the screen's edge.
struct DockIndicated<Icon: View>: View {
    let position: DockPosition
    let isLit: Bool
    @ViewBuilder let icon: Icon

    private var dot: some View {
        Circle().fill(isLit ? Color.primary : .clear).frame(width: 4, height: 4)
    }

    var body: some View {
        switch position {
        case .bottom:
            VStack(spacing: 3) {
                icon
                dot
            }
        case .left:
            HStack(spacing: 3) {
                dot
                icon
            }
        case .right:
            HStack(spacing: 3) {
                icon
                dot
            }
        }
    }
}

/// Jumps until the app is up, away from the screen's edge. Only draws further out, so nothing around it moves.
struct LaunchBounce: ViewModifier {
    let isActive: Bool
    let size: CGFloat
    var position = DockPosition.bottom
    /// A fixed height from 0 to 1 in place of the motion, for snapshots.
    var pose: Double?
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    func body(content: Content) -> some View {
        let height = size * DockBarLayout.bounce
        let isStill = reducesMotion
        let direction = direction
        content.keyframeAnimator(initialValue: pose ?? 0, repeating: isActive && pose == nil) { view, lift in
            view
                .offset(
                    x: isStill ? 0 : height * lift * direction.width,
                    y: isStill ? 0 : height * lift * direction.height
                )
                .opacity(isStill ? 1 - lift / 2 : 1)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1, duration: 0.28)
                CubicKeyframe(0, duration: 0.28)
                LinearKeyframe(0, duration: 0.08)
            }
        }
    }

    private var direction: CGSize {
        switch position {
        case .bottom: CGSize(width: 0, height: -1)
        case .left: CGSize(width: 1, height: 0)
        case .right: CGSize(width: -1, height: 0)
        }
    }
}

struct AppTile: View {
    let app: DockApp
    let size: CGFloat
    let isRunning: Bool
    var isLaunching = false
    var position = DockPosition.bottom
    var pose: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DockIndicated(position: position, isLit: isRunning || isLaunching) {
                AppIcon(app: app, size: size)
                    .modifier(LaunchBounce(isActive: isLaunching, size: size, position: position, pose: pose))
            }
        }
        .buttonStyle(.plain)
        .help(app.name)
    }
}

/// Right-click on an app. Holding ⌥ swaps Hide and Quit for their stronger forms, as in the system Dock.
struct DockAppMenu: View {
    let app: DockApp
    let actions: DockActions

    var body: some View {
        let commands = actions.commands(app)
        if commands.contains(.open) {
            button(loc("Open"), .open)
        }
        if commands.contains(.showAllWindows) {
            button(loc("Show All Windows"), .showAllWindows)
        }
        if commands.contains(.hide) {
            button(loc("Hide"), .hide).modifierKeyAlternate(.option) {
                button(loc("Hide Others"), .hideOthers)
            }
            Divider()
        }
        button(loc("Show in Finder"), .showInFinder)
        if commands.contains(.quit) {
            Divider()
            button(loc("Quit"), .quit).modifierKeyAlternate(.option) {
                button(loc("Force Quit"), .forceQuit)
            }
        }
    }

    private func button(_ title: String, _ command: DockAppCommand) -> some View {
        Button(title) { actions.perform(command, app) }
    }
}

/// Glass square with a 3×3 grid of the folder's first apps.
struct FolderTile: View {
    let folder: AppFolder
    let size: CGFloat
    let isRunning: Bool
    var isLaunching = false
    var position = DockPosition.bottom
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DockIndicated(position: position, isLit: isRunning || isLaunching) {
                content
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.14), in: .rect(cornerRadius: size / 4.5))
                    .modifier(LaunchBounce(isActive: isLaunching, size: size, position: position))
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
                            DockAppMenu(app: app, actions: actions)
                            Divider()
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

/// Live mini view of a module. Click runs its quick action, press and hold opens its card.
struct WidgetTile: View {
    let module: ModuleID
    let size: CGFloat
    let monitor: SystemMonitor
    var position = DockPosition.bottom
    let click: () -> Void
    let hold: () -> Void
    @State private var press = DockPress()

    var body: some View {
        let content = ItemContent.content(module, monitor: monitor, style: .compact)
        Button {
            if press.released() {
                click()
            }
        } label: {
            DockIndicated(position: position, isLit: false) {
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
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture(minimumDuration: DockPress.holdDuration).onEnded { _ in
            press.held()
            hold()
        })
        .onHover { isInside in
            if !isInside {
                press.left()
            }
        }
        .help(module.title)
    }
}
