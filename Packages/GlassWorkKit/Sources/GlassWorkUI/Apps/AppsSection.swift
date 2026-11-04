import Charts
import GlassWorkCore
import SwiftUI

/// Figure on a small card above the list.
struct SummaryCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

/// The last hour of one app in its row. Skips redrawing while its points stay the same: they change once a minute,
/// the figures next to it more often.
struct AppSparkline: View, Equatable {
    let points: [History<Double>.Point]
    let sort: AppUsageSort
    var hover: Date?

    nonisolated static func == (first: AppSparkline, second: AppSparkline) -> Bool {
        first.points == second.points && first.sort == second.sort && first.hover == second.hover
    }

    private var format: (Double) -> String {
        switch sort {
        case .cpu: Format.corePercent
        case .memory: Format.size
        }
    }

    var body: some View {
        InteractiveChart(
            series: [ChartSeries(
                id: "app",
                title: sort == .cpu ? loc("CPU") : loc("Memory"),
                color: Palette.blue,
                points: points,
                format: format
            )],
            height: 28,
            tooltipDate: Date.FormatStyle(date: .omitted, time: .shortened),
            initialHover: hover
        )
    }
}

extension AppUsagePoint {
    func chartPoint(_ sort: AppUsageSort) -> History<Double>.Point {
        History.Point(date: date, value: sort == .cpu ? cpu : memory)
    }
}

/// Column widths, shared by the header and the rows.
private enum Column {
    static let cpu: CGFloat = 52
    static let memory: CGFloat = 72
    static let hour: CGFloat = 120
    static let quit: CGFloat = 84
}

/// What every app uses right now, heaviest first.
public struct AppsSection: View {
    private let monitor: SystemMonitor
    private let open: (AppUsage) -> Void
    private let now: Date?
    private let hoveredID: AppUsage.ID?
    private let sparklineHover: Date?
    @State private var sort = AppUsageSort.memory
    @State private var held: [AppUsage.ID]?

    /// - Parameter now: A fixed moment for tests, and `hoveredID` and `sparklineHover` start them in the hover state.
    public init(
        monitor: SystemMonitor,
        now: Date? = nil,
        hoveredID: AppUsage.ID? = nil,
        sparklineHover: Date? = nil,
        open: @escaping (AppUsage) -> Void
    ) {
        self.monitor = monitor
        self.now = now
        self.hoveredID = hoveredID
        self.sparklineHover = sparklineHover
        self.open = open
    }

    private var apps: [AppUsage] {
        let sorted = monitor.apps.apps.sorted(by: sort)
        return held.map { sorted.arranged(following: $0) } ?? sorted
    }

    public var body: some View {
        MainSectionPage(
            heading: loc("What your apps use"),
            message: loc("Every running app, heaviest first. Helpers count with the app they belong to.")
        ) {
            cards
            table
        }
    }

    private var cards: some View {
        HStack(spacing: 10) {
            SummaryCard(title: loc("CPU"), value: monitor.cpu.map { Format.percent($0.total) } ?? "–")
            SummaryCard(title: loc("Memory"), value: memory)
            SummaryCard(title: loc("Apps running"), value: "\(monitor.apps.apps.count)")
        }
    }

    private var memory: String {
        guard let memory = monitor.memory else { return "–" }
        let used = Format.bytes(Double(memory.used), style: .precise)
        return loc("\(used) of \(Format.bytes(Double(memory.total), style: .precise))")
    }

    private var table: some View {
        VStack(spacing: 0) {
            header
            if monitor.apps.apps.isEmpty {
                Text(loc("Reading what apps use…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(apps) { app in
                row(app)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
        // Holding the order keeps a row from sliding away from under the pointer as Quit is clicked.
        .onHover { held = $0 ? apps.map(\.id) : nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(loc("App")).frame(maxWidth: .infinity, alignment: .leading)
            sortButton(loc("CPU"), .cpu).frame(width: Column.cpu, alignment: .trailing)
            sortButton(loc("Memory"), .memory).frame(width: Column.memory, alignment: .trailing)
            Text(loc("1 hour")).frame(width: Column.hour, alignment: .leading)
            Spacer().frame(width: Column.quit)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(height: 26)
    }

    private func sortButton(_ title: String, _ value: AppUsageSort) -> some View {
        Button {
            sort = value
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == value {
                    Image(systemName: "arrow.down").font(.system(size: 9, weight: .semibold))
                }
            }
            .fontWeight(sort == value ? .semibold : .regular)
            .lineLimit(1)
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func row(_ app: AppUsage) -> some View {
        let since = (now ?? Date()).addingTimeInterval(-3600)
        let points = monitor.apps.points(for: app.id, since: since, limit: 30).map { $0.chartPoint(sort) }
        return AppsTableRow(
            app: app,
            points: points,
            sort: sort,
            startsHovered: app.id == hoveredID,
            sparklineHover: app.id == hoveredID ? sparklineHover : nil
        ) { open(app) }
    }
}

private struct AppsTableRow: View {
    let app: AppUsage
    let points: [History<Double>.Point]
    let sort: AppUsageSort
    let startsHovered: Bool
    let sparklineHover: Date?
    let open: () -> Void
    @State private var isHovered: Bool?

    private var isActive: Bool {
        isHovered ?? startsHovered
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                AppGlyph(app: app, size: 24)
                Text(app.name).font(.system(size: 13)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.corePercent(app.cpu)).frame(width: Column.cpu, alignment: .trailing)
            Text(Format.size(Double(app.memory))).frame(width: Column.memory, alignment: .trailing)
            AppSparkline(points: points, sort: sort, hover: sparklineHover)
                .equatable()
                .frame(width: Column.hour, height: 28)
            // Keeps the column when there is no button, or the row would not line up with the others.
            Color.clear
                .frame(width: Column.quit, height: 1)
                .overlay(alignment: .leading) {
                    if isActive, !app.isProtected {
                        QuitCapsule(app: app)
                    }
                }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .frame(height: 32)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .onTapGesture(perform: open)
        // The sparkline's readout hangs below the row and has to stay above the next one.
        .zIndex(isActive ? 1 : 0)
    }
}
