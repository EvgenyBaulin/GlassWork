import SwiftUI
import WidgetKit

/// Circular progress ring with an optional centered label.
public struct RingGauge<Label: View>: View {
    private let value: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let label: Label

    public init(value: Double, tint: Color, lineWidth: CGFloat = 10, @ViewBuilder label: () -> Label) {
        self.value = min(max(value, 0), 1)
        self.tint = tint
        self.lineWidth = lineWidth
        self.label = label()
    }

    public var body: some View {
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
        .padding(lineWidth / 2)
    }
}

public extension RingGauge where Label == EmptyView {
    init(value: Double, tint: Color, lineWidth: CGFloat = 10) {
        self.init(value: value, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}
