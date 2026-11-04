import AppKit
import GlassWorkCore
import SwiftUI

/// How far back the charts of one app reach.
public enum AppHistoryRange: CaseIterable, Sendable {
    case hour, day, week

    var duration: TimeInterval {
        switch self {
        case .hour: 3600
        case .day: 86400
        case .week: AppUsageHistory.retention
        }
    }

    var title: String {
        switch self {
        case .hour: loc("1 h")
        case .day: loc("24 h")
        case .week: loc("7 days")
        }
    }

    /// A week's peak needs its day.
    func text(_ date: Date) -> String {
        switch self {
        case .hour, .day: date.formatted(date: .omitted, time: .shortened)
        case .week: date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
    }
}

/// A chart of one figure in a card, with its highest moment above it.
private struct AppHistoryCard: View {
    let title: String
    let peak: String?
    let series: ChartSeries
    let hover: Date?

    /// Two points make a line.
    private var hasHistory: Bool {
        series.points.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let peak {
                    Text(peak).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if hasHistory {
                InteractiveChart(
                    series: [series],
                    height: 140,
                    tooltipDate: Date.FormatStyle(date: .abbreviated, time: .shortened),
                    initialHover: hover
                )
            } else {
                Text(loc("History builds up while GlassWork runs."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}

/// One app: what it uses now, its history, and the ways to end it.
public struct AppDetail: View {
    private let id: AppUsage.ID
    private let name: String
    private let monitor: SystemMonitor
    private let now: Date?
    private let hover: Date?
    @State private var range: AppHistoryRange
    @State private var isConfirmingForceQuit = false
    @Environment(\.panelActions) private var actions

    /// A chart cannot show more than its width, and it redraws on every move of the pointer.
    private static let pointLimit = 300

    /// - Parameter now: A fixed moment for tests, and `hover` starts them in the hover state.
    public init(
        id: AppUsage.ID,
        name: String,
        monitor: SystemMonitor,
        range: AppHistoryRange = .day,
        now: Date? = nil,
        hover: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.monitor = monitor
        self.now = now
        self.hover = hover
        _range = State(initialValue: range)
    }

    private var app: AppUsage? {
        monitor.apps.apps.first { $0.id == id }
    }

    private var points: [AppUsagePoint] {
        monitor.apps.history.points(for: id, since: (now ?? Date()).addingTimeInterval(-range.duration))
    }

    public var body: some View {
        let points = points
        let thin = AppUsageHistory.thinned(points, limit: Self.pointLimit)
        MainSectionPage(heading: name, message: summary) {
            Picker("", selection: $range) {
                ForEach(AppHistoryRange.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            AppHistoryCard(
                title: loc("CPU"),
                peak: peak(points, \.cpu, Format.corePercent),
                series: series(thin, .cpu),
                hover: hover
            )
            AppHistoryCard(
                title: loc("Memory"),
                peak: peak(points, \.memory, Format.size),
                series: series(thin, .memory),
                hover: hover
            )
            buttons
            Text(loc("Hover a chart to read a moment. History stays on this Mac for 7 days."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            loc("Force Quit “\(name)”?"),
            isPresented: $isConfirmingForceQuit
        ) {
            Button(loc("Force Quit"), role: .destructive) {
                if let app {
                    actions.quit(app.target, true)
                }
            }
            Button(loc("Cancel"), role: .cancel) {}
        } message: {
            Text(loc("Unsaved work in this app will be lost."))
        }
    }

    private var summary: String {
        guard let app else { return loc("Not running right now.") }
        let memory = Format.size(Double(app.memory))
        let now = loc("\(memory) of memory and \(Format.corePercent(app.cpu)) of CPU right now")
        return app.helpers > 0 ? "\(now), \(loc("with \(app.helpers) helper processes"))." : "\(now)."
    }

    private func peak(
        _ points: [AppUsagePoint],
        _ value: KeyPath<AppUsagePoint, Double>,
        _ format: (Double) -> String
    ) -> String? {
        guard let top = points.max(by: { $0[keyPath: value] < $1[keyPath: value] }) else { return nil }
        return loc("Peak \(format(top[keyPath: value])) at \(range.text(top.date))")
    }

    private func series(_ points: [AppUsagePoint], _ sort: AppUsageSort) -> ChartSeries {
        ChartSeries(
            id: sort == .cpu ? "cpu" : "memory",
            title: sort == .cpu ? loc("CPU") : loc("Memory"),
            color: Palette.blue,
            points: points.map { $0.chartPoint(sort) },
            format: { sort == .cpu ? Format.corePercent($0) : Format.size($0) }
        )
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            let canQuit = app.map { !$0.isProtected } ?? false
            Button(loc("Quit")) {
                if let app {
                    actions.quit(app.target, false)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canQuit)
            Button(loc("Force Quit")) { isConfirmingForceQuit = true }
                .disabled(!canQuit)
            Button(loc("Show in Finder")) {
                if let path = app?.path {
                    actions.showInFinder(path)
                }
            }
            .disabled(app?.path == nil)
            if app?.isProtected == true {
                Text(loc("The Mac or GlassWork needs this one, so it stays."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
