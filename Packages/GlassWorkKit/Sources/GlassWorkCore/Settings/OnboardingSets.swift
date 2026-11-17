import Foundation

/// A group of modules the welcome offers to switch on together.
public enum OnboardingSet: String, CaseIterable, Sendable, Identifiable {
    case developer, day, mac

    public var id: String {
        rawValue
    }

    public var group: ModuleGroup {
        switch self {
        case .developer: .developer
        case .day: .yourDay
        case .mac: .system
        }
    }

    /// Every module of the group, so the sets follow the module list as it grows.
    public var modules: [ModuleID] {
        ModuleID.allCases.filter { $0.group == group }
    }

    /// Modules that go to the menu bar. The rest of the group goes to the Hub.
    public var menuBarModules: Set<ModuleID> {
        switch self {
        case .developer: [.git, .devServers]
        case .day: [.calendar]
        case .mac: [.overview, .cpu, .memory, .battery]
        }
    }

    /// Raises modules, never lowers them: a module already in the menu bar stays there and one in the Hub
    /// only moves up. Modules of sets that were not picked are left alone.
    public static func apply(_ sets: Set<OnboardingSet>, to settings: inout AppSettings) {
        for set in sets {
            for id in set.modules {
                let wanted: ModuleMode = set.menuBarModules.contains(id) ? .menuBar : .hubOnly
                settings.update(id) { module in
                    switch (module.mode, wanted) {
                    case (.off, _), (.hubOnly, .menuBar): module.mode = wanted
                    default: break
                    }
                }
            }
        }
    }

    /// What the chosen sets will ask macOS for, once applied.
    public static func permissions(of sets: Set<OnboardingSet>, in settings: AppSettings) -> Set<Permission> {
        var applied = settings
        apply(sets, to: &applied)
        return PermissionNeeds.needed(byModules: sets.flatMap(\.modules), in: applied)
    }
}
