import GlassWorkCore
import SwiftUI

/// The next hours of rain as bars; hovering one names the hour and how much falls.
struct IslandRainChart: View {
    let rain: IslandRain
    var initialHover: Date?

    private var hasAmounts: Bool {
        rain.hours.contains { $0.amount != nil }
    }

    private var points: [History<Double>.Point] {
        rain.hours.map { History<Double>.Point(date: $0.date, value: $0.amount ?? ($0.isWet ? 1 : 0)) }
    }

    var body: some View {
        InteractiveChart(
            series: [ChartSeries(
                id: "rain", title: loc("Rain"), color: Palette.blue, points: points, format: format
            )],
            domain: 0 ... max(points.map(\.value).max() ?? 1, 1),
            height: 56,
            tooltipDate: Date.FormatStyle(date: .omitted, time: .shortened).regional,
            style: .bars(unit: .hour),
            initialHover: initialHover
        )
    }

    private func format(_ value: Double) -> String {
        if hasAmounts {
            return loc("\(value.formatted(.number.precision(.fractionLength(1)))) mm")
        }
        return value > 0 ? loc("rain") : loc("dry")
    }
}
