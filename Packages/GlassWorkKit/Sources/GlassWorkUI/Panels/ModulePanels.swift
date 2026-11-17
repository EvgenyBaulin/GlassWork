import GlassWorkCore
import SwiftUI

/// The click panel of a module.
public struct ModulePanel: View {
    private let module: ModuleID
    private let monitor: SystemMonitor

    public init(module: ModuleID, monitor: SystemMonitor) {
        self.module = module
        self.monitor = monitor
    }

    public var body: some View {
        switch module {
        case .overview: OverviewPanel(monitor: monitor)
        case .cpu: CPUPanel(monitor: monitor)
        case .memory: MemoryPanel(monitor: monitor)
        case .disk: DiskPanel(monitor: monitor)
        case .network: NetworkPanel(monitor: monitor)
        case .battery: BatteryPanel(monitor: monitor)
        case .gpu: GPUPanel(monitor: monitor)
        case .sensors: SensorsPanel(monitor: monitor)
        case .fans: FansPanel(monitor: monitor)
        case .uptime: UptimePanel(monitor: monitor)
        case .timers: TimersPanel(monitor: monitor)
        case .deviceBatteries: DeviceBatteriesPanel(monitor: monitor)
        case .calendar: CalendarPanel(monitor: monitor)
        case .endsIn: EndsInPanel(monitor: monitor)
        case .todos: TodosPanel(monitor: monitor)
        case .notes: NotesPanel(monitor: monitor)
        case .countdown: CountdownPanel(monitor: monitor)
        case .worldClocks: WorldClocksPanel(monitor: monitor)
        case .date: DatePanel(monitor: monitor)
        case .sunMoon: SunMoonPanel(monitor: monitor)
        case .colours: ColoursPanel(monitor: monitor)
        case .eject: EjectPanel(monitor: monitor)
        case _ where ModuleID.developerCollected.contains(module):
            DeveloperPanel(module: module, store: monitor.developer)
        case .weather: WeatherPanel(store: monitor.weather)
        case .rates: RatesPanel(store: monitor.rates)
        case .clipboard: ClipboardPanel(store: monitor.clipboard)
        case .shelf: ShelfPanel(store: monitor.shelf)
        case .nowPlaying: NowPlayingPanel(store: monitor.nowPlaying)
        default: EmptyView()
        }
    }
}

struct CPUPanel: View {
    let monitor: SystemMonitor
    @AppStorage(PanelRange.cpu) private var range = TieredHistory.Range.minute
    @Environment(\.panelActions) private var actions

    var body: some View {
        CPUPanelContent(
            cpu: monitor.cpu,
            info: monitor.cpuInfo,
            loadAverage: monitor.loadAverage,
            apps: monitor.apps.apps,
            history: monitor.apps.history,
            options: actions.moduleOptions(.cpu),
            points: { monitor.points(.cpu, in: $0) },
            reachesBeforeStart: { monitor.reachesBeforeStart(.cpu, in: $0) },
            range: range,
            setRange: { range = $0 }
        )
    }
}

/// The CPU panel for a reading. Its range is kept by the caller, so the panel opens where it was left.
struct CPUPanelContent: View {
    let cpu: CPUSample?
    let info: CPUInfo
    let loadAverage: [Double]
    let apps: [AppUsage]
    /// What each app used by the minute, for the busiest app at a moment of the chart.
    let history: AppUsageHistory
    let options: [String: String]
    let points: (TieredHistory.Range) -> [History<Double>.Point]
    let reachesBeforeStart: (TieredHistory.Range) -> Bool
    var range = TieredHistory.Range.minute
    var setRange: (TieredHistory.Range) -> Void = { _ in }
    /// Starts the chart as if the cursor were on this moment, for tests of the hover state.
    var initialHover: Date?
    @Environment(\.panelActions) private var actions

    var body: some View {
        let shown = points(range)
        PanelFrame(
            module: .cpu,
            subtitle: subtitle,
            footerTitle: loc("Open Activity Monitor"),
            footerAction: { actions.openApp("com.apple.ActivityMonitor") }
        ) {
            BigFigure(text: cpu.map { Format.percent($0.total) } ?? "—")
            if let cpu, options.flag(ItemOption.splitsUserSystem, default: true) {
                Text(
                    loc(
                        "User \(Format.percent(cpu.user)) · System \(Format.percent(cpu.system)) · Idle \(Format.percent(cpu.idle))"
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            RangePicker(range: Binding(get: { range }, set: setRange))
            InteractiveChart(
                series: [
                    ChartSeries(
                        id: "cpu",
                        title: loc("CPU"),
                        color: Palette.blue,
                        points: shown,
                        format: { Format.percent($0, style: .precise) }
                    ),
                    topAppSeries(shown),
                ],
                domain: 0 ... 1,
                initialHover: initialHover
            )
            RangeSummary(
                stats: RangeStats(shown),
                reachesBeforeStart: reachesBeforeStart(range),
                format: { Format.percent($0, style: .precise) }
            )
            Divider()
            PanelSection(
                title: loc("Cores"),
                caption: loc(
                    "\(info.performanceCores) Performance · \(info.efficiencyCores) Efficiency"
                )
            ) {
                CoreBars(
                    cores: cpu?.cores ?? [],
                    info: info,
                    showsEfficiency: options.flag(ItemOption.showsEfficiencyCores, default: true)
                )
            }
            Divider()
            PanelSection(title: loc("Using the most")) {
                TopApps(apps: apps, sort: .cpu, limit: options.number(ItemOption.topApps, default: 4))
            }
            if loadAverage.count == 3 {
                Text(
                    loc(
                        "Load average  \(loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " · "))"
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
        }
    }

    /// The busiest app at the hovered moment, in the readout only. The value of each point is its time, and the
    /// readout looks the app up from it, so nothing is searched until the cursor is over the chart.
    private func topAppSeries(_ shown: [History<Double>.Point]) -> ChartSeries {
        ChartSeries(
            id: "top-app",
            title: loc("Top app"),
            color: Palette.cyan,
            points: shown.map { History<Double>.Point(date: $0.date, value: $0.date.timeIntervalSince1970) },
            isPlotted: false,
            format: { topApp(at: Date(timeIntervalSince1970: $0)) }
        )
    }

    private func topApp(at date: Date) -> String {
        guard let busiest = history.busiest(at: date) else { return "—" }
        let name = apps.first { $0.id == busiest.id }?.name
            ?? busiest.id.split(separator: ".").last.map(String.init) ?? busiest.id
        return "\(name) \(String(format: "%.0f", busiest.cpu))%"
    }

    private var subtitle: String {
        loc("\(info.brand) · \(cpu?.cores.count ?? 0) cores")
    }
}

/// One vertical bar per core; hovering a bar shows its load.
struct CoreBars: View {
    let cores: [Double]
    let info: CPUInfo
    var showsEfficiency = true
    @State private var hovered: Int?

    /// macOS numbers efficiency cores first on Apple silicon.
    private var ordered: [Core] {
        cores.enumerated().map { index, load in
            Core(index: index, load: load, isPerformance: index >= info.efficiencyCores)
        }
        .sorted { $0.isPerformance && !$1.isPerformance }
        .filter { showsEfficiency || $0.isPerformance }
    }

    private struct Core {
        let index: Int
        let load: Double
        let isPerformance: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(ordered, id: \.index) { core in
                    bar(core.load, tint: core.isPerformance ? Palette.blue : Palette.cyan, index: core.index)
                }
            }
            .frame(height: 52)
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var caption: String {
        guard let hovered, cores.indices.contains(hovered) else {
            return showsEfficiency ? loc("P-cores, then E-cores") : loc("Performance cores")
        }
        return loc("Core \(hovered + 1): \(Format.percent(cores[hovered], style: .precise))")
    }

    private func bar(_ load: Double, tint: Color, index: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                RoundedRectangle(cornerRadius: 3)
                    .fill(tint.opacity(hovered == nil || hovered == index ? 1 : 0.35))
                    .frame(height: max(geometry.size.height * load, 2))
            }
        }
        .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
    }
}

struct MemoryPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        let memory = monitor.memory
        PanelFrame(
            module: .memory,
            subtitle: loc("\(Format.bytes(Double(memory?.total ?? 0), style: .precise)) unified memory"),
            footerTitle: loc("Open Activity Monitor"),
            footerAction: { actions.openApp("com.apple.ActivityMonitor") }
        ) {
            BigFigure(text: Format.percent(memory?.usedShare ?? 0))
            if let memory {
                Text(
                    loc(
                        "\(Format.bytes(Double(memory.used), style: .precise)) of \(Format.bytes(Double(memory.total), style: .precise)) in use"
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                pressure(memory)
                Divider()
                breakdown(memory)
            }
            Divider()
            PanelSection(title: loc("Using the most")) {
                TopApps(apps: monitor.apps.apps, sort: .memory, limit: 4)
            }
        }
    }

    private func pressure(_ memory: MemorySample) -> some View {
        let (title, tint): (String, Color) = switch memory.pressure {
        case .normal: (loc("Low"), Palette.green)
        case .warning: (loc("Medium"), Palette.orange)
        case .critical: (loc("High"), Palette.red)
        }
        return PanelSection(title: loc("Memory pressure"), caption: title) {
            InteractiveChart(
                series: [ChartSeries(
                    id: "memory",
                    title: loc("Used"),
                    color: tint,
                    points: monitor.points(.memory, in: .minute),
                    format: { Format.percent($0, style: .precise) }
                )],
                domain: 0 ... 1,
                height: 36
            )
        }
    }

    private func breakdown(_ memory: MemorySample) -> some View {
        let parts = [
            MemoryPart(title: loc("App"), bytes: memory.app, tint: Palette.green),
            MemoryPart(title: loc("Wired"), bytes: memory.wired, tint: Palette.orange),
            MemoryPart(title: loc("Compressed"), bytes: memory.compressed, tint: Palette.purple),
            MemoryPart(title: loc("Cached"), bytes: memory.cached, tint: Palette.cyan),
        ]
        return PanelSection(title: loc("Breakdown")) {
            StackedBar(
                parts: parts.map { StackedPart(title: $0.title, bytes: $0.bytes, tint: $0.tint) },
                total: memory.total
            )
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { legend(parts[0]); legend(parts[1]) }
                GridRow { legend(parts[2]); legend(parts[3]) }
            }
            if actions.moduleOptions(.memory).flag(ItemOption.showsSwap, default: true) {
                InfoRow(
                    title: loc("Swap used"),
                    value: loc(
                        "\(Format.bytes(Double(memory.swapUsed), style: .precise)) of \(Format.bytes(Double(memory.swapTotal), style: .precise))"
                    )
                )
            }
        }
    }

    private struct MemoryPart {
        let title: String
        let bytes: UInt64
        let tint: Color
    }

    private func legend(_ part: MemoryPart) -> some View {
        HStack(spacing: 5) {
            Circle().fill(part.tint).frame(width: 7, height: 7)
            Text(part.title).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(Format.bytes(Double(part.bytes), style: .precise)).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct DiskPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        PanelFrame(
            module: .disk,
            subtitle: loc("\(monitor.volumes.count) volumes"),
            footerTitle: loc("Open Disk Utility"),
            footerAction: { actions.openApp("com.apple.DiskUtility") }
        ) {
            ForEach(monitor.volumes) { volume in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: volume.isInternal ? "internaldrive" : "externaldrive")
                            .foregroundStyle(.secondary)
                        Text(volume.name).fontWeight(.semibold).lineLimit(1)
                        Spacer()
                        Text(
                            loc(
                                "\(Format.bytes(Double(volume.free), style: .precise)) free of \(Format.bytes(Double(volume.total), style: .precise))"
                            )
                        )
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    }
                    .font(.system(size: 12))
                    ThinBar(
                        value: 1 - volume.freeShare,
                        tint: volume.freeShare < 0.1 ? Palette.orange : Palette.cyan
                    )
                }
            }
            Divider()
            PanelSection(title: loc("Read · Write"), caption: caption) {
                InteractiveChart(
                    series: [
                        rateSeries("read", loc("Read"), Palette.cyan, .diskRead),
                        rateSeries("write", loc("Write"), Palette.purple, .diskWrite),
                    ],
                    mirrored: true,
                    height: 60
                )
            }
        }
    }

    private var caption: String {
        let activity = monitor.diskActivity
        return "R \(Format.rate(activity?.read ?? 0)) · W \(Format.rate(activity?.write ?? 0))"
    }

    private func rateSeries(_ id: String, _ title: String, _ color: Color, _ metric: Metric) -> ChartSeries {
        ChartSeries(id: id, title: title, color: color, points: monitor.points(metric, in: .minute)) {
            Format.rate($0, style: .precise)
        }
    }
}

struct GPUPanel: View {
    let monitor: SystemMonitor
    @AppStorage(PanelRange.gpu) private var range = TieredHistory.Range.minute

    var body: some View {
        GPUPanelContent(
            gpus: monitor.gpus,
            points: { monitor.points(.gpu, in: $0) },
            range: range,
            setRange: { range = $0 }
        )
    }
}

/// The GPU panel for a list of GPUs. The history is the first GPU's, the one the module shows.
struct GPUPanelContent: View {
    let gpus: [GPUSample]
    let points: (TieredHistory.Range) -> [History<Double>.Point]
    /// Kept by the caller, so the panel opens on the range it was left on.
    var range = TieredHistory.Range.minute
    var setRange: (TieredHistory.Range) -> Void = { _ in }

    var body: some View {
        let first = gpus.first
        PanelFrame(module: .gpu, subtitle: first?.name ?? "") {
            BigFigure(text: first?.utilization.map { Format.percent($0) } ?? "—")
            if first?.isReported == true {
                RangePicker(range: Binding(get: { range }, set: setRange))
                InteractiveChart(
                    series: [ChartSeries(
                        id: "gpu",
                        title: loc("GPU"),
                        color: Palette.purple,
                        points: points(range),
                        format: { Format.percent($0, style: .precise) }
                    )],
                    domain: 0 ... 1
                )
            }
            ForEach(gpus) { gpu in
                Divider()
                block(gpu)
            }
        }
    }

    private func block(_ gpu: GPUSample) -> some View {
        VStack(spacing: 6) {
            if gpus.count > 1 {
                Text(gpu.name)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if gpus.count > 1 || !gpu.isReported {
                InfoRow(title: loc("Utilization"), value: share(gpu.utilization))
            }
            InfoRow(title: loc("Renderer"), value: share(gpu.renderer))
            InfoRow(title: loc("Tiler"), value: share(gpu.tiler))
            InfoRow(
                title: loc("GPU memory"),
                value: gpu.memoryInUse > 0 ? Format.bytes(Double(gpu.memoryInUse), style: .precise) : "—"
            )
        }
    }

    /// A missing figure is not a quiet GPU, so it reads as such instead of 0%.
    private func share(_ value: Double?) -> String {
        value.map { Format.percent($0) } ?? loc("Not reported")
    }
}

struct OverviewPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        PanelFrame(
            module: .overview,
            subtitle: monitor.cpuInfo.brand,
            footerTitle: loc("Open Activity Monitor"),
            footerAction: { actions.openApp("com.apple.ActivityMonitor") }
        ) {
            HStack(spacing: 18) {
                ring(monitor.cpu?.total, Palette.blue, loc("CPU"))
                ring(monitor.memory?.usedShare, Palette.green, loc("Memory"))
                ring(monitor.volumes.first.map { 1 - $0.freeShare }, Palette.cyan, loc("Disk"))
            }
            .frame(maxWidth: .infinity)
            Divider()
            PanelSection(title: loc("Top processes"), caption: loc("% CPU")) {
                TopProcesses(processes: monitor.processes, sort: .cpu, tint: Palette.blue)
            }
        }
    }

    /// No value yet is a dash, not a ring at 0%.
    private func ring(_ value: Double?, _ tint: Color, _ title: String) -> some View {
        VStack(spacing: 6) {
            RingGauge(value: value ?? 0, tint: tint, lineWidth: 7) {
                Text(value.map { Format.percent($0) } ?? "—").font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(width: 76, height: 76)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
