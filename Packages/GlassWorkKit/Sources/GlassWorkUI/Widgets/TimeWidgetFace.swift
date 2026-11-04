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
        case .skyClock: sunWidget { SkyClockWidget(context: context, place: $0) }
        case .dayAndNight: sunWidget { DayAndNightWidget(context: context, place: $0) }
        case .weekend: WeekendWidget(context: context)
        case .progress: ProgressWidget(context: context)
        case .stopwatch: StopwatchWidget(context: context)
        case .pomodoro: PomodoroWidget(context: context)
        case .focusTime: FocusTimeWidget(context: context)
        case .wordOfDay: WordOfDayWidget(context: context)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func sunWidget(@ViewBuilder content: (SunPlace) -> some View) -> some View {
        if let place = SunPlace(context.snapshot) {
            content(place)
        } else {
            NoCityMessage()
        }
    }
}
