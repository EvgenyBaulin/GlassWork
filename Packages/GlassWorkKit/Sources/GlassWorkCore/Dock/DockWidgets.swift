import Foundation

public extension ModuleID {
    /// What can stand in the Dock as a widget. Left out: modules with nothing to show yet, and devices, whose
    /// read may raise a Bluetooth prompt and so stays a choice made in the menu bar.
    static var dockWidgets: [ModuleID] {
        allCases.filter { ![.shelf, .appearance, .deviceBatteries].contains($0) }
    }

    /// Whether holding the tile has a card to open. These two are switches with no panel behind them.
    var hasDockCard: Bool {
        self != .stopwatch && self != .keepAwake
    }
}

/// What the Dock knows when a widget is clicked.
public struct DockWidgetContext: Sendable, Equatable {
    public var timers: [CountdownTimer]
    public var devServers: DevServerReading?
    public var events: [AgendaEvent]

    public init(timers: [CountdownTimer] = [], devServers: DevServerReading? = nil, events: [AgendaEvent] = []) {
        self.timers = timers
        self.devServers = devServers
        self.events = events
    }
}

/// What clicking a widget does. Everything here is something the app already does elsewhere: a click never
/// changes system settings, and developer modules stay read-only.
public enum DockWidgetClick: Sendable, Equatable {
    case showCard
    case perform(WidgetCommand.Action)
    case toggleStopwatch
    case toggleKeepAwake
    case togglePlayback
    case open(URL)

    /// What a click starts when no timer is running.
    public static let timerSeconds = 25.0 * 60
    /// How early a call can be joined from the Dock.
    public static let joinWindow = 5.0 * 60

    public static func resolve(_ module: ModuleID, context: DockWidgetContext, at date: Date) -> DockWidgetClick {
        switch module {
        case .timers:
            .perform(context.timers.first.map { .toggleTimer($0.id) } ?? .startTimer(seconds: timerSeconds))
        case .stopwatch: .toggleStopwatch
        case .keepAwake: .toggleKeepAwake
        case .nowPlaying: .togglePlayback
        case .devServers: firstServer(context.devServers).map(DockWidgetClick.open) ?? .showCard
        case .calendar, .endsIn: joinableCall(context.events, at: date).map(DockWidgetClick.open) ?? .showCard
        default: .showCard
        }
    }

    private static func firstServer(_ reading: DevServerReading?) -> URL? {
        guard case let .servers(servers) = reading else { return nil }
        return servers.lazy.compactMap(\.url).first
    }

    /// The earliest call under way or about to start.
    private static func joinableCall(_ events: [AgendaEvent], at date: Date) -> URL? {
        events
            .filter { !$0.isDeclined && $0.end > date && $0.start.timeIntervalSince(date) <= joinWindow }
            .sorted { $0.start < $1.start }
            .lazy.compactMap(\.callURL).first
    }
}

/// Tells a click from press and hold on a tile.
///
/// A button fires on release, after the hold has already shown its card. So a release counts as a click unless
/// a hold came first. Leaving the tile forgets the hold: a release outside never reaches the button, and would
/// otherwise swallow the next real click.
public struct DockPress: Sendable, Equatable {
    /// Seconds, as the design has it.
    public static let holdDuration = 0.4

    private var didHold = false

    public init() {}

    public mutating func held() {
        didHold = true
    }

    public mutating func left() {
        didHold = false
    }

    /// Returns whether this release is a click.
    public mutating func released() -> Bool {
        defer { didHold = false }
        return !didHold
    }
}

public extension DockSettings {
    /// The widgets on show. Nothing while the Dock is off, so a stored Dock costs no reads, and only what the
    /// Dock offers, so a hand-edited file cannot start a read that may raise a prompt.
    var shownWidgets: Set<ModuleID> {
        guard isEnabled else { return [] }
        return Set(widgets).intersection(ModuleID.dockWidgets)
    }

    /// Widgets in Dock order.
    var widgets: [ModuleID] {
        items.compactMap { item in
            if case let .widget(module) = item {
                return module
            }
            return nil
        }
    }
}

public extension DockLayout {
    /// Replaces the Dock's widgets, in the given order, and leaves everything else where it is.
    static func setting(widgets: [ModuleID], in items: [DockItem]) -> [DockItem] {
        let rest = items.filter { item in
            if case .widget = item {
                return false
            }
            return true
        }
        var seen = Set<ModuleID>()
        return rest + widgets.filter { seen.insert($0).inserted }.map(DockItem.widget)
    }

    static func removing(_ item: DockItem, from items: [DockItem]) -> [DockItem] {
        items.filter { $0 != item }
    }
}
