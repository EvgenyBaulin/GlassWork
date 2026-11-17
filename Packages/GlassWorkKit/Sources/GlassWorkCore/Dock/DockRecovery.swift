import Foundation

/// What to do at launch about a system Dock that a previous run left hidden.
///
/// GlassWork saves the system Dock's settings when its Dock takes over and puts them back on a clean quit, on
/// SIGTERM and from `atexit`. A hard crash (a signal that cannot be caught, a power cut) runs none of those, so the
/// settings are still saved at the next launch: that is the only evidence of an unclean exit, and the only moment
/// there is to repair it. There is no separate helper process, so the system Dock stays hidden between the crash
/// and the next launch.
public enum DockRecovery: Sendable, Equatable {
    case nothing
    /// The marker is left over but the settings are already back. Remove the marker.
    case clearMarker
    /// Restore the system Dock now, and say so.
    case restore

    /// `takesOverAgain`: GlassWork Dock is on, so the system Dock stays hidden as it is and the saved settings stay
    /// the original ones; restoring first would only restart the system Dock twice.
    public static func decide(markerExists: Bool, hasSavedSettings: Bool, takesOverAgain: Bool = false) -> DockRecovery {
        if takesOverAgain, hasSavedSettings {
            return .nothing
        }
        if hasSavedSettings {
            return .restore
        }
        return markerExists ? .clearMarker : .nothing
    }
}
