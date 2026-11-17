import GlassWorkCore
import SwiftUI

struct YearInDotsWidget: View {
    let now: Date
    /// Day of the year (from 1) drawn as if the cursor were on it, for tests of the hover state.
    var initialHoverDay: Int?

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let days = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 3), count: 20), spacing: 3) {
            ForEach(1 ... days, id: \.self) { day in
                Circle()
                    .fill(day < today ? Color.primary.opacity(0.75) : day == today ? Palette.orange : Color.primary
                        .opacity(0.15))
                    .frame(width: 5, height: 5)
                    // The 8 pt hover area of a dot is the pitch of the grid, so the areas tile without gaps.
                    .hoverReadout(initialHover: day == initialHoverDay ? CGPoint(x: 4, y: 4) : nil) { _, _ in
                        DotReadout.yearDay(index: day - 1, now: now).map {
                            [DotReadout.dayRow($0, now: now, tint: Palette.orange).tooltipRow]
                        }
                    }
            }
        }
    }
}
