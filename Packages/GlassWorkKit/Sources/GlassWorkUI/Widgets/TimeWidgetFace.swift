import GlassWorkCore
import SwiftUI

/// Clocks, focus tools and daily facts. Split from `WidgetFace` to keep that switch short.
struct TimeWidgetFace: View {
    let kind: WidgetKind
    let context: TimeContext

    var body: some View {
        switch kind {
        case .clock: AnalogClockWidget(context: context)
        case .numeralsClock: NumeralsClockWidget(context: context)
        case .minimalClock: MinimalClockWidget(context: context)
        case .flipClock: FlipClockWidget(context: context)
        case .skyClock: SkyClockWidget(context: context)
        case .dayAndNight: DayAndNightWidget(context: context)
        default: EmptyView()
        }
    }
}
