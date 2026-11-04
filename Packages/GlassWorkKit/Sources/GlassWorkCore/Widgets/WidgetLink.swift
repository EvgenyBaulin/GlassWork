import Foundation

/// Where a click on a system widget can lead. Nothing else can be reached this way.
public enum WidgetDestination: Sendable, Equatable {
    case module(ModuleID)
    /// Where the widgets that need turning on are turned on. It only shows the pane: asking macOS takes a click there.
    case widgetSettings
    /// A page the system opens by itself. The app never receives this one.
    case web(URL)
}

/// The address a system widget opens when clicked.
public enum WidgetLink {
    private static let scheme = "glasswork"
    private static let moduleHost = "module"
    private static let settingsHost = "settings"
    private static let widgetsPath = "widgets"

    public static func url(for destination: WidgetDestination) -> URL? {
        switch destination {
        case let .module(module): url(for: module)
        case .widgetSettings: URL(string: "\(scheme)://\(settingsHost)/\(widgetsPath)")
        case let .web(url): url
        }
    }

    public static func url(for module: ModuleID) -> URL? {
        URL(string: "\(scheme)://\(moduleHost)/\(module.rawValue)")
    }

    /// Nil for anything else, because any app or web page can open this scheme.
    public static func destination(from url: URL) -> WidgetDestination? {
        guard url.scheme == scheme else { return nil }
        switch url.host() {
        case moduleHost: return ModuleID(rawValue: url.lastPathComponent).map(WidgetDestination.module)
        case settingsHost: return url.lastPathComponent == widgetsPath ? .widgetSettings : nil
        default: return nil
        }
    }

    public static func module(from url: URL) -> ModuleID? {
        guard case let .module(module) = destination(from: url) else { return nil }
        return module
    }
}
