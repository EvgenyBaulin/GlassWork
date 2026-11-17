import GlassWorkCore
import SwiftUI

/// One line of a hover readout, for views outside the chart that show the shared tooltip.
public struct HoverRow: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let value: String
    public let color: Color

    public init(title: String, value: String, color: Color = .secondary) {
        id = title
        self.title = title
        self.value = value
        self.color = color
    }

    var tooltipRow: ChartTooltip.Row {
        ChartTooltip.Row(id: id, title: title, value: value, color: color)
    }
}

/// Where the shared tooltip sits next to the cursor.
enum TooltipPlacement {
    /// 16 pt right of the cursor, flipping left near the edge and staying 8 pt inside the container.
    static func x(_ cursor: CGFloat, width: CGFloat, container: CGFloat) -> CGFloat {
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

    /// Like `x`, but a view narrower than its tooltip gets the tooltip centered on it.
    static func x(forSmallView cursor: CGFloat, width: CGFloat, container: CGFloat) -> CGFloat {
        guard container >= width + 16 else { return (container - width) / 2 }
        return x(cursor, width: width, container: container)
    }

    /// The tooltip goes above the cursor in the lower half of the view and below it in the upper half.
    static func opensAbove(cursorY: CGFloat, container: CGFloat) -> Bool {
        cursorY > container / 2
    }

    /// Top edge of the tooltip, 14 pt from the cursor.
    static func top(cursorY: CGFloat, height: CGFloat, container: CGFloat) -> CGFloat {
        opensAbove(cursorY: cursorY, container: container) ? cursorY - 14 - height : cursorY + 14
    }
}

/// Hover transitions are dropped when the person asks for less motion.
enum HoverMotion {
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.15)
    }

    /// Hover tracking never gets thinner than this, so a 4 pt bar is still easy to hit.
    static let minimumHit: CGFloat = 8

    static func hitSize(of size: CGSize, minimum: CGFloat = minimumHit) -> CGSize {
        CGSize(width: max(size.width, minimum), height: max(size.height, minimum))
    }
}

private struct HoverReadoutModifier: ViewModifier {
    let resolve: (CGPoint, CGSize) -> [ChartTooltip.Row]?
    @State private var location: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(initialHover: CGPoint?, resolve: @escaping (CGPoint, CGSize) -> [ChartTooltip.Row]?) {
        self.resolve = resolve
        _location = State(initialValue: initialHover)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geometry in
                    layer(size: HoverMotion.hitSize(of: geometry.size), own: geometry.size)
                }
            }
            .animation(HoverMotion.animation(reduceMotion: reduceMotion), value: location != nil)
            // Among neighbors (a grid of dots) the hovered one draws its tooltip over the rest.
            .zIndex(location == nil ? 0 : 1)
    }

    /// The tracking layer is centered on the view and at least as big as the minimum hit target.
    private func layer(size: CGSize, own: CGSize) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): location = point
                case .ended: location = nil
                }
            }
            .overlay(alignment: .topLeading) {
                if let location, let rows = resolve(location, size), !rows.isEmpty {
                    ChartTooltip(rows: rows)
                        .fixedSize()
                        .alignmentGuide(.leading) { tip in
                            -TooltipPlacement.x(forSmallView: location.x, width: tip.width, container: size.width)
                        }
                        .alignmentGuide(.top) { tip in
                            -TooltipPlacement.top(cursorY: location.y, height: tip.height, container: size.height)
                        }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: (own.width - size.width) / 2, y: (own.height - size.height) / 2)
    }
}

extension View {
    /// Shows the shared tooltip next to the cursor. `resolve` gets the cursor and the size of the hover area
    /// and returns nil where nothing is under it. `initialHover` starts as if the cursor were there, for tests.
    func hoverReadout(
        initialHover: CGPoint? = nil,
        _ resolve: @escaping (CGPoint, CGSize) -> [ChartTooltip.Row]?
    ) -> some View {
        modifier(HoverReadoutModifier(initialHover: initialHover, resolve: resolve))
    }
}
