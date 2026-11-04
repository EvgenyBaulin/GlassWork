import GlassWorkCore
import SwiftUI

/// What the Overview page shows. A plain value, so the page can be drawn from samples.
struct OverviewReadings {
    typealias Points = [History<Double>.Point]

    var cpu: Double?
    var memoryUsed: Double?
    var memoryTotal: Double?
    var diskFree: Double?
    var download: Double?
    var upload: Double?
    var batteryCharge: Double?
    var isCharging = false
    var celsius: Double?
    var cpuPoints: Points = []
    var memoryPoints: Points = []
    var downloadPoints: Points = []
    var uploadPoints: Points = []
    var temperaturePoints: Points = []
    var apps: [AppUsage] = []
}

extension OverviewReadings {
    @MainActor
    init(monitor: SystemMonitor) {
        cpu = monitor.cpu?.total
        memoryUsed = monitor.memory.map { Double($0.used) }
        memoryTotal = monitor.memory.map { Double($0.total) }
        diskFree = monitor.volumes.first.map { Double($0.free) }
        download = monitor.network?.download
        upload = monitor.network?.upload
        batteryCharge = monitor.battery?.charge
        isCharging = monitor.battery?.isCharging ?? false
        celsius = monitor.sensors?.celsius(for: monitor.temperatureSource)
        cpuPoints = monitor.points(.cpu, in: .minute)
        memoryPoints = monitor.points(.memory, in: .minute)
        downloadPoints = monitor.points(.download, in: .minute)
        uploadPoints = monitor.points(.upload, in: .minute)
        temperaturePoints = monitor.points(.temperature, in: .minute)
        apps = monitor.apps.apps
    }

    private func text(_ value: Double?, _ format: (Double) -> String) -> String {
        value.map(format) ?? "–"
    }

    var cpuText: String {
        text(cpu) { Format.percent($0) }
    }

    var memoryText: String {
        guard let memoryUsed, let memoryTotal else { return "–" }
        return loc("\(Format.size(memoryUsed)) of \(Format.size(memoryTotal))")
    }

    var diskText: String {
        diskFree.map { loc("\(Format.size($0)) free") } ?? "–"
    }

    var networkText: String {
        guard let download, let upload else { return "–" }
        return "↓ \(Format.rate(download))  ↑ \(Format.rate(upload))"
    }

    var batteryText: String? {
        batteryCharge.map { (isCharging ? "⚡︎ " : "") + Format.percent($0) }
    }

    var temperatureText: String {
        text(celsius, Format.temperature)
    }
}

/// The first section of the main window: how the Mac is doing now and over the last minute.
public struct OverviewSection: View {
    private let monitor: SystemMonitor

    public init(monitor: SystemMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        OverviewPage(readings: OverviewReadings(monitor: monitor))
    }
}

/// `chartHover` starts the charts as if the cursor were on them, for tests of the hover state.
struct OverviewPage: View {
    private static let topAppsLimit = 5

    let readings: OverviewReadings
    var chartHover: Date?

    var body: some View {
        MainSectionPage(
            heading: loc("How your Mac is doing"),
            message: loc("Right now and over the last minute.")
        ) {
            cards
            charts
            topApps
        }
    }

    private var cards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryCard(title: loc("CPU"), value: readings.cpuText)
                SummaryCard(title: loc("Memory"), value: readings.memoryText)
                SummaryCard(title: loc("Disk"), value: readings.diskText)
            }
            HStack(spacing: 10) {
                SummaryCard(title: loc("Network"), value: readings.networkText)
                // A Mac without a battery simply has one card less.
                if let battery = readings.batteryText {
                    SummaryCard(title: loc("Battery"), value: battery)
                }
                SummaryCard(title: loc("Temperature"), value: readings.temperatureText)
            }
        }
    }

    private var charts: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                OverviewCard(title: loc("CPU")) {
                    chart([percentSeries("cpu", loc("CPU"), Palette.blue, readings.cpuPoints)], domain: 0 ... 1)
                }
                OverviewCard(title: loc("Memory")) {
                    chart(
                        [percentSeries("memory", loc("Memory"), Palette.green, readings.memoryPoints)],
                        domain: 0 ... 1
                    )
                }
            }
            GridRow {
                OverviewCard(title: loc("Network")) {
                    chart(networkSeries, mirrored: true)
                }
                OverviewCard(title: loc("Temperature")) {
                    chart([temperatureSeries], domain: 20 ... 110)
                }
            }
        }
    }

    private func percentSeries(
        _ id: String,
        _ title: String,
        _ color: Color,
        _ points: OverviewReadings.Points
    ) -> ChartSeries {
        ChartSeries(id: id, title: title, color: color, points: points) { Format.percent($0, style: .precise) }
    }

    private var networkSeries: [ChartSeries] {
        [
            ChartSeries(id: "download", title: loc("Download"), color: Palette.teal, points: readings.downloadPoints) {
                Format.rate($0, style: .precise)
            },
            ChartSeries(id: "upload", title: loc("Upload"), color: Palette.blue, points: readings.uploadPoints) {
                Format.rate($0, style: .precise)
            },
        ]
    }

    private var temperatureSeries: ChartSeries {
        ChartSeries(
            id: "temperature",
            title: loc("Temperature"),
            color: Palette.red,
            points: readings.temperaturePoints,
            format: Format.temperature
        )
    }

    private func chart(
        _ series: [ChartSeries],
        domain: ClosedRange<Double>? = nil,
        mirrored: Bool = false
    ) -> some View {
        InteractiveChart(series: series, domain: domain, mirrored: mirrored, initialHover: chartHover)
    }

    private var topApps: some View {
        OverviewCard(title: loc("Using the most")) {
            if readings.apps.isEmpty {
                Text(loc("Reading what apps use…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            TopApps(apps: readings.apps, sort: .cpu, limit: Self.topAppsLimit)
        }
    }
}

/// A titled block of the page, in the same style as the cards above it.
private struct OverviewCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }
}
