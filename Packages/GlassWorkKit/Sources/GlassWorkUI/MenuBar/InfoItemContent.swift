import GlassWorkCore
import SwiftUI

/// Short text after an item's figure. `color` nil follows the bar, like the rest of the item.
public struct ItemAccent {
    public var text: String
    public var color: Color?

    public init(text: String, color: Color?) {
        self.text = text
        self.color = color
    }
}

/// Weather, Rates and Clipboard: items fed by their own stores instead of the system monitor.
extension ItemContent {
    /// How long the item shows a tick after something was copied.
    private static let copiedFlash: TimeInterval = 3
    private static let lastItemLength = 12

    /// The figure as a style shows it.
    func text(for style: DisplayStyle) -> String {
        guard let prefix, style != .labelled else { return figure }
        return "\(prefix) \(figure)"
    }

    /// Points for the graph styles, or nil for items without a graph.
    func graphValues(_ monitor: SystemMonitor) -> [Double]? {
        values ?? metric.map { monitor.points($0, in: .minute).suffix(30).map(\.value) }
    }

    static func weather(_ store: WeatherStore) -> ItemContent {
        guard let report = store.primaryReport else {
            var empty = ItemContent(figure: "—", template: "-88°")
            empty.isDimmed = store.status == .loading
            return empty
        }
        var content = ItemContent(figure: Format.degrees(report.current.temperature), template: "-88°")
        content.symbol = store.isStale ? "icloud.slash" : report.current.condition.symbol(isDay: report.current.isDay)
        content.label = report.place.isCurrentLocation ? nil : String(report.place.name.prefix(3)).uppercased()
        content.isDimmed = store.isStale
        content.values = report.hours.prefix(12).map(\.temperature)
        content.domain = padded(content.values ?? [])
        return content
    }

    static func rates(_ store: RatesStore) -> ItemContent {
        guard let pair = store.settings.shownPair else { return ItemContent(figure: "—", template: "—") }
        let quote = store.snapshot.quote(for: pair)
        let isOld = store.isStale || store.isUnavailable(pair)
        var content = ItemContent(
            figure: quote.map { Format.exchangeRate($0.value) } ?? "—",
            template: "\(pair.base) \(pair.source == .coinGecko ? "888,888" : "888.88") ↑ 99.9%"
        )
        content.showsSymbol = false
        content.prefix = pair.base
        content.label = pair.base
        content.isDimmed = isOld
        content.accent = accent(quote, isOld: isOld, isMonochrome: store.settings.isMonochrome)
        content.values = quote?.history.map(\.value)
        content.domain = padded(content.values ?? [])
        return content
    }

    private static func accent(_ quote: RateQuote?, isOld: Bool, isMonochrome: Bool) -> ItemAccent {
        guard let quote, !isOld else { return ItemAccent(text: "—", color: nil) }
        let percent = abs(quote.changeShare * 100).formatted(.number.precision(.fractionLength(1)))
        // System green and red adapt to the bar, unlike the panel's green, which is too pale on a light one.
        return ItemAccent(
            text: "\(quote.isUp ? "↑" : "↓") \(percent)%",
            color: isMonochrome ? nil : quote.isUp ? .green : .red
        )
    }

    static func clipboard(_ store: ClipboardStore) -> ItemContent {
        let settings = store.settings
        let count = store.history.entries.count
        var content = ItemContent(figure: "\(count)", template: settings.showsLastItem ? "npm run dev…" : "999")
        if settings.showsLastItem, let last = store.history.entries.first {
            let title = last.kind == .image ? loc("Image") : last.title
            content.figure = title.count > lastItemLength ? "\(title.prefix(lastItemLength - 1))…" : title
        }
        content.isDimmed = !settings.isRecording
        if let copied = store.lastCapture, Date().timeIntervalSince(copied) < copiedFlash {
            content.symbol = "checkmark"
        }
        return content
    }

    /// A range that fills the graph: rates move by a percent, so a scale from zero would show a flat line.
    static func padded(_ values: [Double]) -> ClosedRange<Double>? {
        guard let low = values.min(), let high = values.max() else { return nil }
        let margin = high > low ? (high - low) * 0.15 : max(abs(high) * 0.01, 0.000_1)
        return (low - margin) ... (high + margin)
    }
}
