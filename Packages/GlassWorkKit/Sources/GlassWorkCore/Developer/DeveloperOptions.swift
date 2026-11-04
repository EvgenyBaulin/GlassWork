import Foundation

/// Developer module choices, read from `ModuleSettings.options`.
public struct DeveloperOptions: Sendable, Equatable {
    public enum Key {
        public static let host = "host"
        public static let refreshMinutes = "refreshMinutes"
        public static let repository = "repository"
        public static let repositories = "repositories"
    }

    public var pingHost = PingHost.fallback

    public init() {}

    public init(settings: AppSettings) {
        if let host = settings.module(.ping)?.options[Key.host], PingHost.isValid(host) {
            pingHost = host
        }
    }
}

public extension ModuleID {
    /// Modules read by `DeveloperStore`.
    static let developerCollected: Set<ModuleID> = [.aiUsage, .git, .devServers, .docker, .ping, .vpn, .wifi]
}

public extension AppSettings {
    /// A module in the Hub only reads while a panel or the Hub is open, so Ping stays silent the rest of the time.
    func developerDemand(panelOpen: Bool) -> Set<ModuleID> {
        Set(modules.filter { setting in
            ModuleID.developerCollected.contains(setting.id)
                && (setting.mode == .menuBar || (panelOpen && setting.mode == .hubOnly))
        }.map(\.id))
    }
}
