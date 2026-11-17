import Foundation

/// The help text of a menu bar item: "CPU 23% · min 4% · max 91% since 09:12".
enum ItemTooltip {
    struct Extremes: Equatable {
        var low: Double
        var high: Double
        var since: Date?

        /// Nil while there is nothing to compare.
        init?(_ values: [Double], since: Date?) {
            guard let low = values.min(), let high = values.max() else { return nil }
            self.low = low
            self.high = high
            self.since = since
        }
    }

    static func text(
        title: String,
        figure: String,
        extremes: Extremes?,
        format: (Double) -> String,
        secondLine: String? = nil,
        detail: String? = nil,
        timeStyle: Date.FormatStyle = Date.FormatStyle(date: .omitted, time: .shortened).regional
    ) -> String {
        var text = "\(title) \(figure)"
        if let extremes {
            text += " · \(loc("min")) \(format(extremes.low)) · \(loc("max")) \(format(extremes.high))"
            if let since = extremes.since {
                text += " \(loc("since \(since.formatted(timeStyle))"))"
            }
        }
        if let secondLine {
            text += "\n\(secondLine)"
        }
        if let detail {
            text += "\n\(detail)"
        }
        return text
    }
}
