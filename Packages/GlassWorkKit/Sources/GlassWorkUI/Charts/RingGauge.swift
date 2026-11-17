import GlassWorkCore
import SwiftUI
import WidgetKit

/// Names (and optional amounts) of the two parts of a ring, for its hover readout.
public struct RingReadout: Equatable {
    public enum Part: Equatable {
        case used, free
    }

    public let usedTitle: String
    public let freeTitle: String
    public let usedValue: String?
    public let freeValue: String?

    public init(usedTitle: String, freeTitle: String, usedValue: String? = nil, freeValue: String? = nil) {
        self.usedTitle = usedTitle
        self.freeTitle = freeTitle
        self.usedValue = usedValue
        self.freeValue = freeValue
    }

    /// Name, amount when known, and share of the hovered part.
    func row(for part: Part, value: Double, tint: Color) -> ChartTooltip.Row {
        let share = part == .used ? value : 1 - value
        let amount = part == .used ? usedValue : freeValue
        let text = amount.map { "\($0) · \(Format.percent(share))" } ?? Format.percent(share)
        return ChartTooltip.Row(
            id: part == .used ? "used" : "free",
            title: part == .used ? usedTitle : freeTitle,
            value: text,
            color: part == .used ? tint : .secondary
        )
    }
}

/// Which part of a ring is under the cursor.
enum RingHit {
    /// `point` is in the ring's own space; the stroke is centered on the circle that fills `size`.
    /// The band is at least `HoverMotion.minimumHit` wide so thin rings stay easy to hit.
    static func part(at point: CGPoint, size: CGSize, lineWidth: CGFloat, value: Double) -> RingReadout.Part? {
        let offsetX = point.x - size.width / 2
        let offsetY = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = (offsetX * offsetX + offsetY * offsetY).squareRoot()
        let half = max(lineWidth, HoverMotion.minimumHit) / 2
        guard abs(distance - radius) <= half else { return nil }
        // Clockwise from twelve o'clock, like the trimmed stroke.
        var angle = atan2(offsetX, -offsetY)
        if angle < 0 {
            angle += 2 * .pi
        }
        return angle / (2 * .pi) <= value ? .used : .free
    }
}

/// Circular progress ring with an optional centered label.
/// With a `readout`, hovering the ring names the part under the cursor with its amount and share.
public struct RingGauge<Label: View>: View {
    private let value: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let readout: RingReadout?
    private let initialHover: CGPoint?
    private let label: Label

    public init(
        value: Double,
        tint: Color,
        lineWidth: CGFloat = 10,
        readout: RingReadout? = nil,
        initialHover: CGPoint? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.value = min(max(value, 0), 1)
        self.tint = tint
        self.lineWidth = lineWidth
        self.readout = readout
        self.initialHover = initialHover
        self.label = label()
    }

    public var body: some View {
        ring
            .padding(lineWidth / 2)
    }

    @ViewBuilder
    private var ring: some View {
        if let readout {
            drawn.hoverReadout(initialHover: initialHover) { point, size in
                RingHit.part(at: point, size: size, lineWidth: lineWidth, value: value)
                    .map { [readout.row(for: $0, value: value, tint: tint)] }
            }
        } else {
            drawn
        }
    }

    private var drawn: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            label
        }
    }
}

public extension RingGauge where Label == EmptyView {
    init(value: Double, tint: Color, lineWidth: CGFloat = 10, readout: RingReadout? = nil) {
        self.init(value: value, tint: tint, lineWidth: lineWidth, readout: readout) { EmptyView() }
    }
}
