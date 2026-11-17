import Foundation

/// The steps before the Dock is turned on for the first time.
public enum DockFirstRunStep: Sendable, Equatable {
    /// What the Dock does to the system one.
    case intro
    /// Waits for Accessibility, which badges and the window menu need.
    case accessibility
    /// Starts from a preset, or from none.
    case preset

    /// The step after this one, or nil when the Dock can be turned on. Accessibility is asked for only while it is
    /// not granted, and the preset only when there are presets to choose from.
    public func next(isTrusted: Bool, hasPresets: Bool) -> DockFirstRunStep? {
        switch self {
        case .intro:
            if !isTrusted {
                return .accessibility
            }
            return hasPresets ? .preset : nil
        case .accessibility:
            return hasPresets ? .preset : nil
        case .preset:
            return nil
        }
    }
}
