import Foundation

/// A small reading the opened island can show when no event is on screen.
public enum IslandMiniWidget: String, CaseIterable, Sendable, Identifiable {
    case upNext, weather, rates, cpu, memory, battery

    public var id: String {
        rawValue
    }
}

/// The widgets the user chose, in order. Ids this version does not know are kept for a newer one.
public struct IslandMiniSet: Codable, Sendable, Equatable {
    public static let defaultIDs = [IslandMiniWidget.upNext, .weather, .rates].map(\.rawValue)

    public private(set) var ids: [String]

    public init(ids: [String] = IslandMiniSet.defaultIDs) {
        self.ids = ids
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        ids = (try? container.decode([String].self)) ?? Self.defaultIDs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(ids)
    }

    /// Chosen widgets this version can draw, in the chosen order, once each.
    public var shown: [IslandMiniWidget] {
        var seen: Set<String> = []
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return IslandMiniWidget(rawValue: id)
        }
    }

    /// Known widgets that are not chosen, for the "Add widget" list.
    public var hidden: [IslandMiniWidget] {
        let chosen = shown
        return IslandMiniWidget.allCases.filter { !chosen.contains($0) }
    }

    public func contains(_ widget: IslandMiniWidget) -> Bool {
        ids.contains(widget.rawValue)
    }

    public mutating func toggle(_ widget: IslandMiniWidget) {
        if contains(widget) {
            ids.removeAll { $0 == widget.rawValue }
        } else {
            ids.append(widget.rawValue)
        }
    }

    /// Moves a chosen widget one place earlier (`-1`) or later (`1`); the ends stay put.
    public mutating func move(_ widget: IslandMiniWidget, by step: Int) {
        guard let index = ids.firstIndex(of: widget.rawValue) else { return }
        let target = index + step
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
    }
}

/// What one mini widget says. Text that needs a translation (condition, high and low) stays as values.
public struct IslandMiniReading: Sendable, Equatable {
    public var widget: IslandMiniWidget
    public var value: String
    public var detail: String
    public var date: Date?
    public var condition: WeatherCondition?
    public var high: String?
    public var low: String?

    public init(widget: IslandMiniWidget, value: String, detail: String = "") {
        self.widget = widget
        self.value = value
        self.detail = detail
    }

    /// Readings that exist in the input. A widget without data is left out, never shown empty.
    public static func readings(from input: IslandInput, now: Date) -> [IslandMiniWidget: IslandMiniReading] {
        var result: [IslandMiniWidget: IslandMiniReading] = [:]
        if let next = EndsInState(events: input.calendarEvents, at: now).next {
            var reading = IslandMiniReading(widget: .upNext, value: "", detail: next.title)
            reading.date = next.start
            result[.upNext] = reading
        }
        if let report = input.weather {
            var reading = IslandMiniReading(widget: .weather, value: Format.degrees(report.current.temperature))
            reading.condition = report.current.condition
            reading.high = report.days.first.map { Format.degrees($0.high) }
            reading.low = report.days.first.map { Format.degrees($0.low) }
            result[.weather] = reading
        }
        if let first = input.rates.first {
            result[.rates] = IslandMiniReading(
                widget: .rates, value: rate(first),
                detail: input.rates.dropFirst().first.map(rate) ?? ""
            )
        }
        if let cpu = input.cpu {
            result[.cpu] = IslandMiniReading(widget: .cpu, value: Format.percent(cpu.total))
        }
        if let memory = input.memory, memory.total > 0 {
            result[.memory] = IslandMiniReading(
                widget: .memory, value: Format.percent(Double(memory.used) / Double(memory.total)),
                detail: Format.size(Double(memory.used))
            )
        }
        if let battery = input.battery {
            result[.battery] = IslandMiniReading(widget: .battery, value: Format.percent(battery.charge))
        }
        return result
    }

    private static func rate(_ quote: RateQuote) -> String {
        "\(quote.pair.base) \(Format.exchangeRate(quote.value))"
    }
}
