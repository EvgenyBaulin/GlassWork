import Foundation

/// Decides when the Mac should be dark if the Appearance module follows the sun.
public enum SunAppearance {
    /// Whether it should be dark at `date`: from sunset until the next sunrise. Nil where the sun does not rise
    /// or set, as in a polar night, since then there is nothing to follow.
    public static func wantsDark(at date: Date, latitude: Double, longitude: Double) -> Bool? {
        Astronomy.nextEvent(.next, after: date, latitude: latitude, longitude: longitude).map { $0.event == .sunrise }
    }

    /// The look to switch to now, or nil to leave things as they are. A switch happens when the sun's side of
    /// the day changes, and on the first look after the option was turned on. Between those, a click on the
    /// Appearance item stays in force until the next sunrise or sunset.
    public static func change(wanted: Bool?, last: Bool?) -> Bool? {
        guard let wanted, wanted != last else { return nil }
        return wanted
    }
}
