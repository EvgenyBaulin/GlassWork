import SwiftUI

/// One day's temperature span on a scale shared by the whole week, with an optional marker for now.
struct DayRangeBar: View {
    let low: Double
    let high: Double
    let scale: ClosedRange<Double>
    var current: Double?
    var isDimmed = false

    private func share(_ value: Double) -> CGFloat {
        let span = max(scale.upperBound - scale.lowerBound, 0.000_1)
        return min(max((value - scale.lowerBound) / span, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 4)
                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.cyan, Palette.orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(width * (share(high) - share(low)), 4), height: 4)
                    .offset(x: width * share(low))
                    .opacity(isDimmed ? 0.4 : 1)
                if let current {
                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .offset(x: width * share(current) - 3.5)
                }
            }
        }
        .frame(height: 7)
    }
}
