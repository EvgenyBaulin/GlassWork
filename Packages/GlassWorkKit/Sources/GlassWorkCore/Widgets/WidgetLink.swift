import Foundation

/// The address a system widget opens when clicked. It can only name a module's panel.
public enum WidgetLink {
    private static let scheme = "glasswork"
    private static let host = "module"

    public static func url(for module: ModuleID) -> URL? {
        URL(string: "\(scheme)://\(host)/\(module.rawValue)")
    }

    /// Nil for anything else, because any app or web page can open this scheme.
    public static func module(from url: URL) -> ModuleID? {
        guard url.scheme == scheme, url.host() == host else { return nil }
        return ModuleID(rawValue: url.lastPathComponent)
    }
}
