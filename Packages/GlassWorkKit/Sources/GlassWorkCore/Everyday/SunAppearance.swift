import Foundation

/// Decides when the Mac should be dark if the Appearance module follows the sun.
public enum SunAppearance {
    /// Whether it should be dark at `date`: from sunset until the next sunrise. Nil where the sun does not rise
    /// or set, as in a polar night, since then there is nothing to follow.
    public static func wantsDark(at date: Date, latitude: Double, longitude: Double) -> Bool? {
        Astronomy.nextEvent(.next, after: date, latitude: latitude, longitude: longitude).map { $0.event == .sunrise }
    }

    /// What one look at the sun decides.
    public struct Look: Equatable, Sendable {
        /// The look to switch to, or nil to leave things as they are.
        public var dark: Bool?
        /// The next sunrise or sunset, to hand back at the next look. Nil when there is nothing to follow.
        public var nextEvent: Date?
    }

    /// A switch happens on the first look after the option was turned on, and whenever the sunrise or sunset
    /// that was next has passed, however long ago: a Mac that slept through a sunrise still gets it on waking.
    /// Between those, a click on the Appearance item stays in force until the next sunrise or sunset.
    public static func look(at date: Date, latitude: Double, longitude: Double, nextEvent: Date?) -> Look {
        guard let upcoming = Astronomy.nextEvent(.next, after: date, latitude: latitude, longitude: longitude) else {
            return Look(dark: nil, nextEvent: nil)
        }
        if let nextEvent, date < nextEvent {
            return Look(dark: nil, nextEvent: nextEvent)
        }
        return Look(dark: upcoming.event == .sunrise, nextEvent: upcoming.date)
    }
}
