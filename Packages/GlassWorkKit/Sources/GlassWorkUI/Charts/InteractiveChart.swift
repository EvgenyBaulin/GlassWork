import Charts
import GlassWorkCore
import SwiftUI

/// One line of a chart.
public struct ChartSeries: Identifiable {
    public let id: String
    public let title: String
    public let color: Color
    public let points: [History<Double>.Point]
    public let format: (Double) -> String
    /// False for a value shown only in the hover readout, such as Ping's loss next to its latency.
    public let isPlotted: Bool

    public init(
        id: String,
        title: String,
        color: Color,
        points: [History<Double>.Point],
        isPlotted: Bool = true,
        format: @escaping (Double) -> String
    ) {
        self.id = id
        self.title = title
        self.color = color
        self.points = points
        self.isPlotted = isPlotted
        self.format = format
    }

    /// The point closest to a moment, used to snap the hover readout.
    public func nearest(to date: Date) -> History<Double>.Point? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Area chart that shows the value under the cursor and returns to normal when it leaves.
///
/// With two series and `mirrored`, the second one grows downwards on its own scale.
public struct InteractiveChart: View {
    private let series: [ChartSeries]
    private let domain: ClosedRange<Double>?
    private let mirrored: Bool
    private let height: CGFloat
    private let tooltipDate: Date.FormatStyle
    @State private var hover: Date?

    /// `initialHover` starts the chart as if the cursor were there, for tests of the hover state.
    public init(
        series: [ChartSeries],
        domain: ClosedRange<Double>? = nil,
        mirrored: Bool = false,
        height: CGFloat = 76,
        tooltipDate: Date.FormatStyle = Date.FormatStyle(date: .omitted, time: .standard),
        initialHover: Date? = nil
    ) {
        self.series = series
        self.domain = domain
        self.mirrored = mirrored
        self.height = height
        self.tooltipDate = tooltipDate
        _hover = State(initialValue: initialHover)
    }

    public var body: some View {
        chart
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: yDomain)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    hoverLayer(proxy: proxy, geometry: geometry)
                }
            }
            .frame(height: height)
            .animation(.easeOut(duration: 0.15), value: hover == nil)
    }

    private var plottedSeries: [ChartSeries] {
        series.filter(\.isPlotted)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(plottedSeries.enumerated()), id: \.element.id) { index, line in
                ForEach(line.points, id: \.date) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Base", mirrored ? 0 : yDomain.lowerBound),
                        yEnd: .value("Value", plotted(point.value, index: index)),
                        series: .value("Series", line.id)
                    )
                    .foregroundStyle(line.color.opacity(hover == nil ? 0.28 : 0.16))
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Value", plotted(point.value, index: index)),
                        series: .value("Series", line.id)
                    )
                    .foregroundStyle(line.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
            if let hover {
                RuleMark(x: .value("Cursor", hover))
                    .foregroundStyle(.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(Array(plottedSeries.enumerated()), id: \.element.id) { index, line in
                    if let point = line.nearest(to: hover) {
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Value", plotted(point.value, index: index))
                        )
                        .foregroundStyle(line.color)
                        .symbolSize(36)
                    }
                }
            }
        }
    }

    private var yDomain: ClosedRange<Double> {
        if mirrored {
            return -1.05 ... 1.05
        }
        if let domain {
            return domain
        }
        return 0 ... max((plottedSeries.flatMap(\.points).map(\.value).max() ?? 1) * 1.1, 0.000_1)
    }

    /// Mirrored series are normalized separately, otherwise the smaller one lies flat on the axis.
    private func plotted(_ value: Double, index: Int) -> Double {
        guard mirrored else { return value }
        let peak = max(plottedSeries[index].points.map(\.value).max() ?? 1, 0.000_1)
        return value / peak * (index == 0 ? 1 : -1)
    }

    private func hoverLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hover = snapped(proxy.value(atX: location.x, as: Date.self))
                    case .ended:
                        hover = nil
                    }
                }
            if let hover, let position = proxy.position(forX: hover) {
                ChartTooltip(date: hover, rows: tooltipRows(at: hover), dateStyle: tooltipDate)
                    .fixedSize()
                    .alignmentGuide(.leading) { size in
                        -tooltipX(position, width: size.width, container: geometry.size.width)
                    }
                    .offset(y: height < Self.tallEnoughForTooltip ? height + 4 : 0)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Below this the tooltip would sit on the cursor, so it goes under the chart instead.
    private static let tallEnoughForTooltip: CGFloat = 50

    private func snapped(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return series.first?.nearest(to: date)?.date
    }

    private func tooltipRows(at date: Date) -> [ChartTooltip.Row] {
        series.compactMap { line in
            line.nearest(to: date).map {
                ChartTooltip.Row(id: line.id, title: line.title, value: line.format($0.value), color: line.color)
            }
        }
    }

    /// 16 pt right of the cursor, flipping left near the edge and staying 8 pt inside the chart.
    private func tooltipX(_ cursor: CGFloat, width: CGFloat, container: CGFloat) -> CGFloat {
        let right = cursor + 16
        if right + width <= container - 8 {
            return right
        }
        let left = cursor - 16 - width
        if left >= 8 {
            return left
        }
        return min(max(cursor - width / 2, 8), max(container - width - 8, 8))
    }
}

/// Dense glass readout: plain glass is unreadable over a chart.
struct ChartTooltip: View {
    struct Row: Identifiable {
        let id: String
        let title: String
        let value: String
        let color: Color
    }

    var date: Date?
    let rows: [Row]
    var dateStyle = Date.FormatStyle(date: .omitted, time: .standard)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Circle().fill(row.color).frame(width: 6, height: 6)
                    Text(row.title).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value).fontWeight(.semibold).monospacedDigit()
                }
            }
            if let date {
                Text(date.formatted(dateStyle))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.12)))
    }
}

/// Small line used in the menu bar and in tiles.
public struct Sparkline: View {
    private let values: [Double]
    private let domain: ClosedRange<Double>?
    private let color: Color
    private let filled: Bool

    public init(values: [Double], domain: ClosedRange<Double>? = nil, color: Color = .primary, filled: Bool = true) {
        self.values = values
        self.domain = domain
        self.color = color
        self.filled = filled
    }

    public var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let upper = domain?.upperBound ?? max(values.max() ?? 1, 0.000_1)
            let lower = domain?.lowerBound ?? 0
            let step = size.width / CGFloat(values.count - 1)
            var line = Path()
            for (index, value) in values.enumerated() {
                let share = (value - lower) / max(upper - lower, 0.000_1)
                let point = CGPoint(x: CGFloat(index) * step, y: size.height * (1 - min(max(share, 0), 1)))
                if index == 0 {
                    line.move(to: point)
                } else {
                    line.addLine(to: point)
                }
            }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(color.opacity(0.3)))
            }
            context.stroke(line, with: .color(color), lineWidth: 1)
        }
    }
}

/// Thin progress bar with an optional hover readout.
public struct ThinBar: View {
    private let value: Double
    private let tint: Color
    private let height: CGFloat

    public init(value: Double, tint: Color, height: CGFloat = 4) {
        self.value = min(max(value, 0), 1)
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint).frame(width: max(geometry.size.width * value, value > 0 ? height : 0))
            }
        }
        .frame(height: height)
    }
}
