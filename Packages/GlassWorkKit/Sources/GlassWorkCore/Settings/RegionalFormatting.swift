import Foundation

public extension Date.FormatStyle {
    /// The same style, written with the clock the user chose. Identical to the style itself on System.
    var regional: Date.FormatStyle {
        regional(RegionalFormat.settings)
    }

    func regional(_ settings: RegionalSettings, base: Locale = .current) -> Date.FormatStyle {
        var style = self
        style.locale = settings.locale(base: base)
        return style
    }
}

public extension Date {
    /// The time of day, like `14:05` or `2:05 PM`, in the user's clock.
    var timeText: String {
        timeText(using: RegionalFormat.settings)
    }

    /// A short date and the time of day, in the user's clock.
    var dateTimeText: String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).regional)
    }

    func timeText(using settings: RegionalSettings, base: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened).regional(settings, base: base)
        style.timeZone = timeZone
        return formatted(style)
    }
}
