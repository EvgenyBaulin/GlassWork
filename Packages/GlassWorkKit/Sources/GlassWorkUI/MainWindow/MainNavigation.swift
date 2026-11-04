import GlassWorkCore
import Observation
import SwiftUI

/// The main window's sidebar. To add a section: add a case here, fill in the two switches, and give it a view in
/// the app's `MainWindowContent`.
public enum MainSection: String, CaseIterable, Identifiable, Sendable {
    case overview, apps, clipboard, windowTiles, unlock, widgets, dock, settings

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .overview: loc("Overview")
        case .apps: loc("Apps")
        case .clipboard: loc("Clipboard")
        case .windowTiles: loc("Window Tiles")
        case .unlock: loc("Unlock")
        case .widgets: loc("Widgets")
        case .dock: loc("Dock")
        case .settings: loc("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .apps: "square.stack.3d.up"
        case .clipboard: "list.clipboard"
        case .windowTiles: "rectangle.split.2x2"
        case .unlock: "lock.open"
        case .widgets: "square.grid.2x2"
        case .dock: "dock.rectangle"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .overview, .settings: Palette.gray
        case .apps: Palette.blue
        case .clipboard: Palette.orange
        case .windowTiles: Palette.teal
        case .unlock: Palette.red
        case .widgets: Palette.purple
        case .dock: Palette.green
        }
    }

    /// Settings has its own window, so choosing it opens that and leaves this one where it was.
    var opensOwnWindow: Bool {
        self == .settings
    }

    /// What this section reads while it is on screen. The rest of the app does not ask for most of it.
    public var monitorDemand: MonitorDemand {
        var demand = MonitorDemand()
        switch self {
        case .apps:
            demand.cpu = true
            demand.memory = true
            demand.liveApps = true
        case .overview:
            demand.cpu = true
            demand.memory = true
            demand.network = true
            demand.disk = true
            demand.sensors = true
            demand.liveApps = true
        default:
            break
        }
        return demand
    }
}

/// Where the main window is: a section, and something inside it such as one app.
public struct MainRoute: Hashable, Sendable {
    public struct Item: Hashable, Sendable {
        public let id: String
        public let title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public var section: MainSection
    public var item: Item?

    public init(section: MainSection, item: Item? = nil) {
        self.section = section
        self.item = item
    }

    public var title: String {
        guard let item else { return section.title }
        return "\(section.title) › \(item.title)"
    }
}

/// Places visited, for the back and forward buttons. Going somewhere new drops what lay ahead.
struct RouteHistory: Equatable {
    private(set) var routes: [MainRoute]
    private(set) var position = 0

    /// Enough to walk back through a session without growing for as long as the app stays open.
    private static let limit = 50

    init(start: MainRoute) {
        routes = [start]
    }

    var current: MainRoute {
        routes[position]
    }

    var canGoBack: Bool {
        position > 0
    }

    var canGoForward: Bool {
        position < routes.count - 1
    }

    mutating func go(to route: MainRoute) {
        guard route != current else { return }
        routes.removeSubrange((position + 1)...)
        routes.append(route)
        if routes.count > Self.limit {
            routes.removeFirst()
        }
        position = routes.count - 1
    }

    mutating func goBack() {
        if canGoBack {
            position -= 1
        }
    }

    mutating func goForward() {
        if canGoForward {
            position += 1
        }
    }
}

/// What the main window shows. The app reads it to know when a section's data is on screen.
@MainActor
@Observable
public final class MainNavigation {
    private var history: RouteHistory

    /// Called after every move.
    @ObservationIgnored public var onChange: (() -> Void)?

    public init(start: MainRoute = MainRoute(section: .apps)) {
        history = RouteHistory(start: start)
    }

    public var route: MainRoute {
        history.current
    }

    public var canGoBack: Bool {
        history.canGoBack
    }

    public var canGoForward: Bool {
        history.canGoForward
    }

    public func go(to route: MainRoute) {
        history.go(to: route)
        onChange?()
    }

    public func goBack() {
        history.goBack()
        onChange?()
    }

    public func goForward() {
        history.goForward()
        onChange?()
    }
}
