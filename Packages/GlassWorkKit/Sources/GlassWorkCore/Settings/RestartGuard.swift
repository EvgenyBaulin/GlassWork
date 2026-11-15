import Foundation

/// Decides whether a launch after a crash goes ahead. launchd brings GlassWork back after every crash and has
/// no limit of its own, so a crash right at launch would loop forever without this.
public struct RestartGuard: Sendable, Equatable, Codable {
    public static let window: TimeInterval = 600
    public static let limit = 3

    /// Launches that followed a crash, within the window.
    public private(set) var restarts: [Date] = []
    /// Set when the app quits normally, cleared at launch.
    public private(set) var quitCleanly = true

    public init() {}

    public enum Decision: Sendable, Equatable {
        case run
        /// Too many crashes in a row: stay down until the user opens the app.
        case giveUp
    }

    /// Call once at launch. `byKeeper` is true when launchd started this run.
    public mutating func launch(at date: Date, byKeeper: Bool) -> Decision {
        defer { quitCleanly = false }
        restarts.removeAll { date.timeIntervalSince($0) > Self.window || $0 > date }
        // Opened by the user, or by launchd at login after a normal quit: a fresh start.
        guard byKeeper, !quitCleanly else {
            restarts.removeAll()
            return .run
        }
        guard restarts.count < Self.limit else { return .giveUp }
        restarts.append(date)
        return .run
    }

    public mutating func quit() {
        quitCleanly = true
        restarts.removeAll()
    }
}
