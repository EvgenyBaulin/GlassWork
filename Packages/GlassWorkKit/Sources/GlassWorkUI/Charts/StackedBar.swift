import GlassWorkCore
import SwiftUI

/// One colored part of a `StackedBar`.
struct StackedPart: Equatable {
    let title: String
    let bytes: UInt64
    let tint: Color
}

/// Where the parts of a stacked bar lie, and which one is under the cursor.
enum StackedBarLayout {
    static let spacing: CGFloat = 1

    /// The horizontal extent of each part. Parts are laid out left to right with `spacing` between them.
    static func spans(_ parts: [StackedPart], total: UInt64, width: CGFloat) -> [ClosedRange<CGFloat>] {
        var spans: [ClosedRange<CGFloat>] = []
        var start: CGFloat = 0
        for part in parts {
            let length = width * CGFloat(part.bytes) / CGFloat(max(total, 1))
            spans.append(start ... start + length)
            start += length + spacing
        }
        return spans
    }

    /// The index of the part under `x`. A pixel of spacing between parts, or the empty end of the bar, hits none.
    static func index(at x: CGFloat, parts: [StackedPart], total: UInt64, width: CGFloat) -> Int? {
        let spans = spans(parts, total: total, width: width)
        return spans.indices.first { parts[$0].bytes > 0 && spans[$0].contains(x) }
    }

    /// Tooltip text: the part's name, its size and its share of the total.
    static func row(for part: StackedPart, total: UInt64) -> ChartTooltip.Row {
        let share = Double(part.bytes) / Double(max(total, 1))
        return ChartTooltip.Row(
            id: part.title,
            title: part.title,
            value: "\(Format.bytes(Double(part.bytes), style: .precise)) · \(Format.percent(share, style: .precise))",
            color: part.tint
        )
    }
}

/// Horizontal bar split into colored parts. Hovering a part names it with its size and share.
struct StackedBar: View {
    let parts: [StackedPart]
    let total: UInt64
    /// Starts as if the cursor were there, for tests.
    var initialHover: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: StackedBarLayout.spacing) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.tint)
                        .frame(width: geometry.size.width * Double(part.bytes) / Double(max(total, 1)))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .hoverReadout(initialHover: initialHover) { point, size in
            guard let index = StackedBarLayout.index(at: point.x, parts: parts, total: total, width: size.width)
            else { return nil }
            return [StackedBarLayout.row(for: parts[index], total: total)]
        }
    }
}
