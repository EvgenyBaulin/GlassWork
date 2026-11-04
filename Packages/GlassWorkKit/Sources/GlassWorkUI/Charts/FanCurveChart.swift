import Charts
import GlassWorkCore
import SwiftUI

/// Temperature against fan speed. Hovering reads the curve; in the editor, points can be dragged.
public struct FanCurveChart: View {
    /// The fan right now, shown as a live dot.
    public struct Live: Equatable {
        public var celsius: Double
        public var rpm: Double

        public init(celsius: Double, rpm: Double) {
            self.celsius = celsius
            self.rpm = rpm
        }
    }

    private let curve: FanCurve
    private let otherCurve: FanCurve?
    private let rpmRange: ClosedRange<Double>
    private let live: Live?
    private let isEditable: Bool
    private let showsAxes: Bool
    private let height: CGFloat
    private let onChange: (FanCurve) -> Void
    @Binding private var selection: Int?
    @State private var hover: Double?
    @State private var dragged: Int?
    @FocusState private var isFocused: Bool

    private static let hitRadius: CGFloat = 14
    private static let tint = Palette.cyan

    public init(
        curve: FanCurve,
        otherCurve: FanCurve? = nil,
        rpmRange: ClosedRange<Double>,
        live: Live? = nil,
        isEditable: Bool = false,
        showsAxes: Bool = false,
        height: CGFloat = 110,
        selection: Binding<Int?> = .constant(nil),
        hover: Double? = nil,
        onChange: @escaping (FanCurve) -> Void = { _ in }
    ) {
        self.curve = curve
        self.otherCurve = otherCurve
        self.rpmRange = rpmRange
        self.live = live
        self.isEditable = isEditable
        self.showsAxes = showsAxes
        self.height = height
        self.onChange = onChange
        _selection = selection
        _hover = State(initialValue: hover)
    }

    public var body: some View {
        chart
            .chartXScale(domain: FanCurve.temperatureRange)
            .chartYScale(domain: FanCurve.percentRange)
            .chartXAxis(showsAxes ? .automatic : .hidden)
            .chartYAxis(showsAxes ? .automatic : .hidden)
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    interactionLayer(proxy: proxy, geometry: geometry)
                }
            }
            .frame(height: height)
            .focusable(isEditable)
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(.delete) { deleteSelection() }
    }

    private var chart: some View {
        Chart {
            RectangleMark(
                xStart: .value("Failsafe", FanEngine.failsafeCelsius),
                xEnd: .value("End", FanCurve.temperatureRange.upperBound),
                yStart: .value("Bottom", FanCurve.percentRange.lowerBound),
                yEnd: .value("Top", FanCurve.percentRange.upperBound)
            )
            .foregroundStyle(Palette.orange.opacity(0.18))
            .annotation(position: .overlay, alignment: .bottomTrailing, spacing: 2) {
                Text(loc("95 °C → Max"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Palette.orange)
                    .fixedSize()
            }
            if let otherCurve {
                ForEach(Array(outline(otherCurve).enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Temperature", point.celsius),
                        y: .value("Speed", point.percent),
                        series: .value("Series", "other")
                    )
                    .foregroundStyle(Self.tint.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            ForEach(Array(outline(curve).enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Temperature", point.celsius),
                    yStart: .value("Base", 0),
                    yEnd: .value("Speed", point.percent),
                    series: .value("Series", "curve")
                )
                .foregroundStyle(Self.tint.opacity(hover == nil ? 0.22 : 0.12))
                LineMark(
                    x: .value("Temperature", point.celsius),
                    y: .value("Speed", point.percent),
                    series: .value("Series", "curve")
                )
                .foregroundStyle(Self.tint)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
            ForEach(Array(curve.points.enumerated()), id: \.offset) { index, point in
                PointMark(x: .value("Temperature", point.celsius), y: .value("Speed", point.percent))
                    .foregroundStyle(index == selection ? Color.accentColor : Self.tint)
                    .symbolSize(index == selection ? 70 : 36)
            }
            if let live {
                PointMark(
                    x: .value("Temperature", clampedTemperature(live.celsius)),
                    y: .value("Speed", curve.percent(at: live.celsius))
                )
                .foregroundStyle(Color.primary)
                .symbolSize(44)
            }
            if let hover {
                RuleMark(x: .value("Cursor", hover))
                    .foregroundStyle(Color.primary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Temperature", hover), y: .value("Speed", curve.percent(at: hover)))
                    .foregroundStyle(Self.tint)
                    .symbolSize(36)
            }
        }
    }

    /// The points, extended flat to both edges of the chart.
    private func outline(_ curve: FanCurve) -> [FanCurve.Point] {
        var points = curve.points
        if let first = points.first, first.celsius > FanCurve.temperatureRange.lowerBound {
            points.insert(.init(celsius: FanCurve.temperatureRange.lowerBound, percent: first.percent), at: 0)
        }
        if let last = points.last, last.celsius < FanCurve.temperatureRange.upperBound {
            points.append(.init(celsius: FanCurve.temperatureRange.upperBound, percent: last.percent))
        }
        return points
    }

    private func clampedTemperature(_ celsius: Double) -> Double {
        min(max(celsius, FanCurve.temperatureRange.lowerBound), FanCurve.temperatureRange.upperBound)
    }

    private func interactionLayer(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let plot = proxy.plotFrame.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case let .active(location):
                        hover = temperature(at: location, proxy: proxy, plot: plot)
                    case .ended:
                        hover = nil
                    }
                }
                .gesture(dragGesture(proxy: proxy, plot: plot))
                .onTapGesture(count: 2) { location in addPoint(at: location, proxy: proxy, plot: plot) }
                .onTapGesture { location in selectPoint(near: location, proxy: proxy, plot: plot) }
            if let readout {
                readoutView(readout, proxy: proxy, plot: plot, width: geometry.size.width)
            }
        }
    }

    private var readout: (celsius: Double, row: ChartTooltip.Row)? {
        if let hover {
            let percent = curve.percent(at: hover)
            let rpm = FanCurve.rpm(percent: percent, in: rpmRange)
            let text = loc("\(Format.percent(percent / 100)) ≈ \(Format.rpm(rpm)) rpm")
            return (hover, .init(id: "hover", title: Format.temperature(hover), value: text, color: Self.tint))
        }
        guard let live else { return nil }
        let row = ChartTooltip.Row(
            id: "live",
            title: loc("now \(Format.temperature(live.celsius))"),
            value: loc("\(Format.rpm(live.rpm)) rpm"),
            color: .primary
        )
        return (clampedTemperature(live.celsius), row)
    }

    private func readoutView(
        _ readout: (celsius: Double, row: ChartTooltip.Row),
        proxy: ChartProxy,
        plot: CGRect,
        width: CGFloat
    ) -> some View {
        let cursor = (proxy.position(forX: readout.celsius) ?? 0) + plot.minX
        return ChartTooltip(date: nil, rows: [readout.row])
            .fixedSize()
            .alignmentGuide(.leading) { size in
                // Flips to the left of the cursor near the edge, as every chart tooltip does.
                let right = cursor + 16
                return -(right + size.width <= width - 8 ? right : max(cursor - 16 - size.width, 8))
            }
            .alignmentGuide(.top) { _ in -(plot.minY + 6) }
            .allowsHitTesting(false)
    }

    private func temperature(at location: CGPoint, proxy: ChartProxy, plot: CGRect) -> Double? {
        guard plot.contains(location) else { return nil }
        return proxy.value(atX: location.x - plot.minX, as: Double.self).map(clampedTemperature)
    }

    private func curvePoint(at location: CGPoint, proxy: ChartProxy, plot: CGRect) -> FanCurve.Point? {
        let relative = CGPoint(x: location.x - plot.minX, y: location.y - plot.minY)
        guard let values = proxy.value(at: relative, as: (Double, Double).self) else { return nil }
        return FanCurve.Point(celsius: values.0.rounded(), percent: values.1.rounded())
    }

    private func nearestPoint(to location: CGPoint, proxy: ChartProxy, plot: CGRect) -> Int? {
        let distances = curve.points.enumerated().compactMap { index, point -> (Int, CGFloat)? in
            guard let position = proxy.position(for: (point.celsius, point.percent)) else { return nil }
            return (index, hypot(position.x + plot.minX - location.x, position.y + plot.minY - location.y))
        }
        return distances.filter { $0.1 <= Self.hitRadius }.min { $0.1 < $1.1 }?.0
    }

    private func dragGesture(proxy: ChartProxy, plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard isEditable else { return }
                let index = dragged ?? nearestPoint(to: value.startLocation, proxy: proxy, plot: plot)
                guard let index, let target = curvePoint(at: value.location, proxy: proxy, plot: plot) else { return }
                dragged = index
                selection = index
                onChange(curve.moving(index, to: target))
            }
            .onEnded { _ in dragged = nil }
    }

    private func selectPoint(near location: CGPoint, proxy: ChartProxy, plot: CGRect) {
        guard isEditable else { return }
        selection = nearestPoint(to: location, proxy: proxy, plot: plot)
        isFocused = true
    }

    private func addPoint(at location: CGPoint, proxy: ChartProxy, plot: CGRect) {
        guard isEditable, let target = curvePoint(at: location, proxy: proxy, plot: plot),
              let added = curve.inserting(target)
        else { return }
        selection = added.points.firstIndex { $0.celsius == target.celsius }
        onChange(added)
    }

    private func deleteSelection() -> KeyPress.Result {
        guard isEditable, let selection, let removed = curve.removing(selection) else { return .ignored }
        self.selection = nil
        onChange(removed)
        return .handled
    }
}
