import GlassWorkCore
import SwiftUI

/// Where a panel keeps the range its picker was left on, so the next opening starts there.
enum PanelRange {
    static let cpu = "panelRange.cpu"
    static let gpu = "panelRange.gpu"
    static let sensors = "panelRange.sensors"
}

/// Min, average and max of what the chart above shows, and a note when the chart starts before the app did.
struct RangeSummary: View {
    let stats: RangeStats?
    let reachesBeforeStart: Bool
    let format: (Double) -> String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                stat(loc("Min"), stats?.minimum)
                stat(loc("Avg"), stats?.average)
                stat(loc("Max"), stats?.maximum)
            }
            if reachesBeforeStart {
                Label(loc("Since launch"), systemImage: "arrow.left.to.line")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help(loc("Chart reaches back before the app started"))
            }
        }
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.map(format) ?? "—").font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
