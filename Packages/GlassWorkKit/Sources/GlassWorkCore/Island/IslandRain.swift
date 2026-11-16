import Foundation

/// Rain the island warns about, read from the hourly forecast the Weather module already keeps.
///
/// The forecast has one entry per hour, so the island speaks in clock times, not minutes.
public struct IslandRain: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// The first wet hour begins at this moment.
        case starts(Date)
        /// It is raining and the last wet hour of this spell ends at this moment.
        case stops(Date)

        /// The moment the island names: when rain begins, or when it ends.
        public var moment: Date {
            switch self {
            case let .starts(date), let .stops(date): date
            }
        }
    }

    public struct Hour: Sendable, Equatable, Identifiable {
        public var date: Date
        /// Millimetres; nil when the forecast did not say.
        public var amount: Double?
        /// Percent from 0 to 100; nil when the forecast did not say.
        public var probability: Double?
        public var isWet: Bool

        public var id: Date {
            date
        }

        public init(date: Date, amount: Double? = nil, probability: Double? = nil, isWet: Bool) {
            self.date = date
            self.amount = amount
            self.probability = probability
            self.isWet = isWet
        }
    }

    public enum Intensity: Sendable, Equatable {
        case light, moderate, heavy
    }

    /// A wet hour needs at least this many millimetres, when the forecast gives amounts.
    public static let amountThreshold = 0.1
    /// ... and at least this chance, in percent.
    public static let probabilityThreshold = 50.0
    /// Rain that starts later than this is not worth a warning yet.
    public static let lookahead: TimeInterval = 3 * 3600
    /// How many hours the card draws.
    public static let shownHours = 6

    public var phase: Phase
    /// When the spell begins; the hour under way counts from its start.
    public var start: Date
    /// When the last wet hour of the spell ends.
    public var end: Date
    public var placeName: String
    /// From the hour under way, as many as the card draws.
    public var hours: [Hour]
    /// The heaviest hour of this spell, millimetres.
    public var peakAmount: Double?

    public init(
        phase: Phase, start: Date, end: Date, placeName: String, hours: [Hour], peakAmount: Double? = nil
    ) {
        self.phase = phase
        self.start = start
        self.end = end
        self.placeName = placeName
        self.hours = hours
        self.peakAmount = peakAmount
    }

    public var intensity: Intensity? {
        guard let peakAmount else { return nil }
        switch peakAmount {
        case ..<0.5: return .light
        case ..<4: return .moderate
        default: return .heavy
        }
    }

    /// Stays the same while one spell is followed, so a refresh of the forecast does not announce it again.
    /// Rain that has started is a new moment worth showing, so it is a key of its own.
    public var key: String {
        switch phase {
        case let .starts(date): "starts:\(Int(date.timeIntervalSince1970))"
        case .stops: "raining"
        }
    }

    /// Nil when the report is missing, has no wet hours soon, or its hours are all past.
    public static func reading(from report: WeatherReport?, now: Date) -> IslandRain? {
        guard let report else { return nil }
        let hours = report.hours.filter { $0.date.addingTimeInterval(3600) > now }
        guard let first = hours.first else { return nil }
        let wet = hours.map { isWet($0) }
        let phase: Phase
        let spell: ArraySlice<HourForecast>
        if first.date <= now, wet[0] {
            spell = hours.prefix(wet.prefix { $0 }.count)
            phase = .stops(spell[spell.endIndex - 1].date.addingTimeInterval(3600))
        } else if let index = wet.indices.first(where: { wet[$0] && hours[$0].date > now }),
                  hours[index].date <= now.addingTimeInterval(lookahead)
        {
            spell = hours[index...].prefix { isWet($0) }
            phase = .starts(hours[index].date)
        } else {
            return nil
        }
        return IslandRain(
            phase: phase,
            start: spell[spell.startIndex].date,
            end: spell[spell.endIndex - 1].date.addingTimeInterval(3600),
            placeName: report.place.name,
            hours: hours.prefix(shownHours).map {
                Hour(
                    date: $0.date, amount: $0.precipitation, probability: $0.precipitationProbability,
                    isWet: isWet($0)
                )
            },
            peakAmount: spell.compactMap(\.precipitation).max()
        )
    }

    /// Amounts decide when the forecast has them; without them, the weather code does. Snow is not rain.
    static func isWet(_ hour: HourForecast) -> Bool {
        switch hour.condition {
        case .snow, .snowShowers: return false
        default: break
        }
        if let amount = hour.precipitation {
            return amount >= amountThreshold && (hour.precipitationProbability ?? 100) >= probabilityThreshold
        }
        switch hour.condition {
        case .drizzle, .rain, .freezingRain, .showers, .thunderstorm: return true
        default: return false
        }
    }
}
