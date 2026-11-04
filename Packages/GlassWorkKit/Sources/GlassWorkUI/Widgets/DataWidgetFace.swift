import GlassWorkCore
import SwiftUI

/// Live readings, developer tools and Screen Time. Split from `WidgetFace` to keep that switch short.
struct DataWidgetFace: View {
    let kind: WidgetKind
    let context: TimeContext

    var body: some View {
        switch kind {
        case .fans: FansWidget(context: context)
        case .weather: WeatherWidget(context: context)
        case .rates: RatesWidget(context: context)
        case .git: GitWidget(context: context)
        case .devServers: DevServersWidget(context: context)
        case .containers: ContainersWidget(context: context)
        case .aiUsage: AIUsageWidget(context: context)
        case .devices: DevicesWidget(context: context)
        case .wifiSignal: WiFiSignalWidget(context: context)
        case .diskActivity: DiskActivityWidget(context: context)
        case .timeMachine: TimeMachineWidget(context: context)
        case .screenTime: ScreenTimeWidget(context: context)
        case .screenTimeWeek: ScreenTimeWeekWidget(context: context)
        case .categories: CategoriesWidget(context: context)
        case .breaks: BreaksWidget(context: context)
        case .appTime: AppTimeWidget(context: context)
        case .mostUsed: MostUsedWidget(context: context)
        default: TimeWidgetFace(kind: kind, context: context)
        }
    }
}
