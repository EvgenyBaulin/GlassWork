import Foundation

/// Where a click on a system widget can lead. Nothing else can be reached this way.
public enum WidgetDestination: Sendable, Equatable {
    case module(ModuleID)
    /// Where the widgets that need turning on are turned on. It only shows the pane: asking macOS takes a click there.
    case widgetSettings
    /// A page in the browser. macOS may open it directly or hand it to the app.
    case web(URL)
}

/// The address a system widget opens when clicked.
public enum WidgetLink {
    private static let scheme = "glasswork"
    private static let moduleHost = "module"
    private static let settingsHost = "settings"
    private static let widgetsPath = "widgets"

    /// Where the GitHub widgets lead when no single pull request was clicked.
    public static let githubHome = URL(string: "https://github.com")
    public static let githubReviews = URL(string: "https://github.com/pulls/review-requested")

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

    /// Also accepts a web address, if the widgets put exactly that address on screen themselves. macOS may hand a
    /// click on a link in a widget to the app, and any app can send the same thing, so nothing else gets through.
    public static func destination(
        from url: URL,
        shownIn snapshot: @autoclosure () -> WidgetSnapshot?
    ) -> WidgetDestination? {
        if let destination = destination(from: url) {
            return destination
        }
        guard url.scheme == "https" else { return nil }
        let shown = snapshot()
        let pulls = ((shown?.github?.requested ?? []) + (shown?.github?.mine ?? [])).compactMap { URL(string: $0.url) }
        let calls = (shown?.events ?? []).compactMap(\.callURL)
        return ([githubHome, githubReviews].compactMap(\.self) + pulls + calls).contains(url) ? .web(url) : nil
    }

    public static func module(from url: URL) -> ModuleID? {
        guard case let .module(module) = destination(from: url) else { return nil }
        return module
    }
}
