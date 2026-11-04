import GlassWorkCore
import SwiftUI

public extension DockPosition {
    var title: String {
        switch self {
        case .bottom: loc("Dock position bottom")
        case .left: loc("Dock position left")
        case .right: loc("Dock position right")
        }
    }
}

public extension ModuleID {
    /// What a click on this widget in the Dock does, for Settings.
    var dockClickTitle: String {
        switch self {
        case .timers: loc("Click: start 25 min")
        case .stopwatch: loc("Click: start or stop")
        case .keepAwake: loc("Click: turn on or off")
        case .nowPlaying: loc("Click: play or pause")
        case .devServers: loc("Click: open in browser")
        case .calendar, .endsIn: loc("Click: join call")
        default: loc("Click: open card")
        }
    }
}

/// What the Dock can ask the app to do.
@MainActor
public struct DockActions {
    public var open: (DockApp) -> Void
    /// A click on a widget runs its quick action.
    public var clickWidget: (ModuleID) -> Void
    /// Press and hold on a widget opens its card.
    public var holdWidget: (ModuleID) -> Void
    public var update: (([DockItem]) -> [DockItem]) -> Void
    /// Tells the window what to make room for.
    public var needsSpace: (DockSpace) -> Void
    /// What the right-click menu offers for an app right now.
    public var commands: (DockApp) -> [DockAppCommand]
    public var perform: (DockAppCommand, DockApp) -> Void
    /// Moves the widgets on show by this many sets.
    public var turnPage: (Int) -> Void
    /// Opens a file from a stack.
    public var openFile: (String) -> Void
    /// Opens a stack's folder in Finder.
    public var showFolder: (String) -> Void

    public init(
        open: @escaping (DockApp) -> Void,
        clickWidget: @escaping (ModuleID) -> Void,
        holdWidget: @escaping (ModuleID) -> Void,
        update: @escaping (([DockItem]) -> [DockItem]) -> Void,
        needsSpace: @escaping (DockSpace) -> Void,
        commands: @escaping (DockApp) -> [DockAppCommand] = { _ in [] },
        perform: @escaping (DockAppCommand, DockApp) -> Void = { _, _ in },
        turnPage: @escaping (Int) -> Void = { _ in },
        openFile: @escaping (String) -> Void = { _ in },
        showFolder: @escaping (String) -> Void = { _ in }
    ) {
        self.open = open
        self.clickWidget = clickWidget
        self.holdWidget = holdWidget
        self.update = update
        self.needsSpace = needsSpace
        self.commands = commands
        self.perform = perform
        self.turnPage = turnPage
        self.openFile = openFile
        self.showFolder = showFolder
    }
}

/// The Dock: apps, folders, stacks and live widgets on a glass bar.
public struct DockView: View {
    private let state: DockLiveState
    private let monitor: SystemMonitor
    private let actions: DockActions
    /// Distance from the middle of the Dock, which stays put however wide the bar gets.
    @State private var pointer: Double?

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
        state.fittedSettings
    }

    private var running: Set<String> {
        state.running
    }

    private var position: DockPosition {
        settings.position
    }

    /// Read fresh from settings, so renaming a folder does not leave the card holding the old one.
    private var openItem: DockItem? {
        settings.items.first { $0.id == state.openCard }
    }

    private var space: DockSpace {
        if openItem != nil {
            return .folder
        }
        return pointer == nil ? .rest : .magnified
    }

    /// The edge of the screen the Dock stands on.
    private var edge: Alignment {
        switch position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// Everything hangs from the screen's edge, so the window can change size without the bar moving.
    public var body: some View {
        GeometryReader { proxy in
            let length = position.isVertical ? proxy.size.height : proxy.size.width
            ZStack(alignment: edge) {
                if let openItem {
                    let offset = cardOffset(of: openItem, windowLength: length)
                    card(openItem)
                        .padding(cardEdge, cardLift)
                        .offset(x: position.isVertical ? 0 : offset, y: position.isVertical ? offset : 0)
                }
                bar(middle: length / 2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: edge)
        }
        .coordinateSpace(.named(Self.canvas))
        .onChange(of: space) { _, space in actions.needsSpace(space) }
    }

    @ViewBuilder
    private func card(_ item: DockItem) -> some View {
        switch item {
        case let .folder(folder):
            FolderCard(folder: folder, actions: actions) { state.openCard = nil }
        case let .stack(stack):
            let card = StackCard(
                stack: stack,
                files: state.files[stack.path] ?? [],
                position: position,
                actions: actions
            ) { state.openCard = nil }
            // A fan stands straight on the desktop.
            if stack.showsFan(at: position) {
                card
            } else {
                card.modifier(PanelGlass())
            }
        case .app, .widget:
            EmptyView()
        }
    }

    /// A card stands by its tile for as far as the window allows.
    private func cardOffset(of item: DockItem, windowLength: Double) -> Double {
        let slots = state.arrangement.slots
        guard let index = slots.firstIndex(of: .item(item)) else { return 0 }
        return DockBarLayout.cardOffset(
            center: DockBarLayout.slotCenter(index, count: slots.count, base: settings.iconSize),
            cardLength: position.isVertical ? DockBarLayout.folderCardHeight : DockBarLayout.folderCardWidth,
            windowLength: windowLength
        )
    }

    private var cardEdge: Edge.Set {
        switch position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var cardLift: Double {
        DockBarLayout.restHeight(base: settings.iconSize) + DockBarLayout.growth(settings) + DockBarLayout.folderCardGap
    }

    private var stack: AnyLayout {
        switch position {
        case .bottom: AnyLayout(HStackLayout(alignment: .bottom, spacing: DockBarLayout.spacing))
        case .left: AnyLayout(VStackLayout(alignment: .leading, spacing: DockBarLayout.spacing))
        case .right: AnyLayout(VStackLayout(alignment: .trailing, spacing: DockBarLayout.spacing))
        }
    }

    private func bar(middle: Double) -> some View {
        let arrangement = state.arrangement
        let layout = DockBarLayout(
            count: arrangement.slots.count,
            base: settings.iconSize,
            magnified: settings.magnifiedSize,
            pointer: settings.magnifies ? pointer : nil
        )
        return stack {
            ForEach(Array(arrangement.slots.enumerated()), id: \.element.id) { index, slot in
                self.slot(slot, size: layout.sizes[index], arrangement: arrangement)
                    .overlay(alignment: position.isVertical ? .bottom : .trailing) {
                        if arrangement.dividers.contains(index) {
                            DockDivider(position: position, length: settings.iconSize)
                        }
                    }
            }
        }
        .padding(DockBarLayout.padding)
        .background(alignment: edge) {
            // Keeps its depth: icons grow out of it, away from the screen's edge.
            let depth = DockBarLayout.restHeight(base: settings.iconSize)
            Color.clear
                .frame(width: position.isVertical ? depth : nil, height: position.isVertical ? nil : depth)
                .glassEffect(.regular, in: .rect(cornerRadius: 22))
        }
        .onContinuousHover(coordinateSpace: .named(Self.canvas)) { phase in
            switch phase {
            case let .active(location): movePointer(to: (position.isVertical ? location.y : location.x) - middle)
            case .ended: movePointer(to: nil)
            }
        }
        .offset(x: position.isVertical ? 0 : layout.centerX, y: position.isVertical ? layout.centerX : 0)
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
    private func slot(_ slot: DockSlot, size: CGFloat, arrangement: DockArrangement) -> some View {
        switch slot {
        case let .item(item):
            tile(item, size: size)
        case .previousPage:
            DockPagerTile(direction: .previous, size: size, arrangement: arrangement, position: position) {
                actions.turnPage(-1)
            }
        case .nextPage:
            DockPagerTile(direction: .next, size: size, arrangement: arrangement, position: position) {
                actions.turnPage(1)
            }
        }
    }

    private func toggleCard(_ item: DockItem) {
        state.openCard = state.openCard == item.id ? nil : item.id
    }

    @ViewBuilder
    private func tile(_ item: DockItem, size: CGFloat) -> some View {
        switch item {
        case let .app(app):
            AppTile(
                app: app,
                size: size,
                isRunning: running.contains(app.path),
                isLaunching: state.launching.contains(app.path),
                position: position
            ) { actions.open(app) }
                .contextMenu { DockAppMenu(app: app, actions: actions) }
                .draggable(app.path)
                .dropDestination(for: String.self) { paths, _ in
                    drop(paths) { dragged, items in DockLayout.drop(dragged, onto: app, in: items) }
                }
        case let .folder(folder):
            FolderTile(
                folder: folder,
                size: size,
                isRunning: folder.apps.contains { running.contains($0.path) },
                isLaunching: folder.apps.contains { state.launching.contains($0.path) },
                position: position
            ) { toggleCard(item) }
                .dropDestination(for: String.self) { paths, _ in
                    drop(paths) { dragged, items in DockLayout.drop(dragged, into: folder, in: items) }
                }
        case let .widget(module):
            WidgetTile(
                module: module,
                size: size,
                monitor: monitor,
                position: position,
                click: { actions.clickWidget(module) },
                hold: { actions.holdWidget(module) }
            )
            .contextMenu {
                Button(loc("Remove from Dock")) { actions.update { DockLayout.removing(item, from: $0) } }
            }
        case let .stack(stack):
            StackTile(stack: stack, files: state.files[stack.path] ?? [], size: size, position: position) {
                toggleCard(item)
            }
            .contextMenu { StackMenu(stack: stack, actions: actions) }
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
