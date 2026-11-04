import Foundation

/// Developer module choices, read from `ModuleSettings.options`.
public struct DeveloperOptions: Sendable, Equatable {
    public enum Key {
        public static let host = "host"
        public static let pingInterval = "intervalSeconds"
        public static let pingTimeout = "timeoutSeconds"
        public static let refreshMinutes = "refreshMinutes"
        public static let repository = "repository"
        public static let repositories = "repositories"
        public static let autoDiscover = "autoDiscover"
        public static let searchDepth = "searchDepth"
    }

    public var pingHost = PingHost.fallback
    public var pingIntervalSeconds = 30
    public var pingTimeoutSeconds = 2
    public var aiRefreshMinutes = 5
    /// The repository shown in the menu bar.
    public var gitRepository: String?
    /// Repositories added by hand, on top of those found in `~/Developer`.
    public var gitRepositories: [String] = []
    /// Off leaves only the repositories added by hand.
    public var gitAutoDiscover = true
    /// How many levels below `~/Developer` to look.
    public var gitSearchDepth = 2

    public init() {}

    public init(settings: AppSettings) {
        if let host = settings.module(.ping)?.options[Key.host], PingHost.isValid(host) {
            pingHost = host
        }
        let ping = settings.module(.ping)?.options ?? [:]
        pingIntervalSeconds = min(max(ping.number(Key.pingInterval, default: 30), 5), 600)
        pingTimeoutSeconds = min(max(ping.number(Key.pingTimeout, default: 2), 1), 10)
        if let minutes = settings.module(.aiUsage)?.options[Key.refreshMinutes].flatMap({ Int($0) }),
           (1 ... 1440).contains(minutes)
        {
            aiRefreshMinutes = minutes
        }
        let git = settings.module(.git)?.options
        gitRepository = git?[Key.repository]
        gitRepositories = Self.decode(git?[Key.repositories])
        gitAutoDiscover = git?.flag(Key.autoDiscover, default: true) ?? true
        gitSearchDepth = git?.number(Key.searchDepth, default: 2) == 1 ? 1 : 2
    }

    /// Options are plain strings, so a list is stored one path per line.
    public static func encode(_ paths: [String]) -> String? {
        paths.isEmpty ? nil : paths.joined(separator: "\n")
    }

    public static func decode(_ text: String?) -> [String] {
        text?.split(whereSeparator: \.isNewline).map(String.init) ?? []
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
