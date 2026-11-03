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
        case .uptime: UptimePanel()
        default: EmptyView()
        }
    }
}

struct CPUPanel: View {
    let monitor: SystemMonitor
    @State private var range = TieredHistory.Range.minute
    @Environment(\.panelActions) private var actions

    var body: some View {
        PanelFrame(
            module: .cpu,
            subtitle: subtitle,
            footerTitle: loc("Open Activity Monitor"),
            footerAction: { actions.openApp("com.apple.ActivityMonitor") }
        ) {
            BigFigure(text: Format.percent(monitor.cpu?.total ?? 0))
            if let cpu = monitor.cpu {
                Text(
                    loc(
                        "User \(Format.percent(cpu.user)) · System \(Format.percent(cpu.system)) · Idle \(Format.percent(cpu.idle))"
                    )
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            RangePicker(range: $range)
            InteractiveChart(
                series: [ChartSeries(
                    id: "cpu",
                    title: loc("CPU"),
                    color: Palette.blue,
                    points: monitor.points(.cpu, in: range),
                    format: { Format.percent($0, style: .precise) }
                )],
                domain: 0 ... 1
            )
            Divider()
            PanelSection(
                title: loc("Cores"),
                caption: loc(
                    "\(monitor.cpuInfo.performanceCores) Performance · \(monitor.cpuInfo.efficiencyCores) Efficiency"
                )
            ) {
                CoreBars(cores: monitor.cpu?.cores ?? [], info: monitor.cpuInfo)
            }
            Divider()
            PanelSection(title: loc("Top processes"), caption: loc("% CPU")) {
                TopProcesses(processes: monitor.processes, sort: .cpu, tint: Palette.blue)
            }
            if monitor.loadAverage.count == 3 {
                Text(
                    loc(
                        "Load average  \(monitor.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " · "))"
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var subtitle: String {
        loc("\(monitor.cpuInfo.brand) · \(monitor.cpu?.cores.count ?? 0) cores")
    }
}

/// One vertical bar per core; hovering a bar shows its load.
struct CoreBars: View {
    let cores: [Double]
    let info: CPUInfo
    @State private var hovered: Int?

    /// macOS numbers efficiency cores first on Apple silicon.
    private var ordered: [Core] {
        cores.enumerated().map { index, load in
            Core(index: index, load: load, isPerformance: index >= info.efficiencyCores)
        }
        .sorted { $0.isPerformance && !$1.isPerformance }
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
        guard let hovered, cores.indices.contains(hovered) else { return loc("P-cores, then E-cores") }
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
            PanelSection(title: loc("Top processes"), caption: loc("Memory")) {
                TopProcesses(processes: monitor.processes, sort: .memory, tint: Palette.green, limit: 4)
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
            StackedBar(parts: parts.map { ($0.bytes, $0.tint) }, total: memory.total)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { legend(parts[0]); legend(parts[1]) }
                GridRow { legend(parts[2]); legend(parts[3]) }
            }
            InfoRow(
                title: loc("Swap used"),
                value: loc(
                    "\(Format.bytes(Double(memory.swapUsed), style: .precise)) of \(Format.bytes(Double(memory.swapTotal), style: .precise))"
                )
            )
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

/// Horizontal bar split into colored parts.
struct StackedBar: View {
    let parts: [(UInt64, Color)]
    let total: UInt64

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.1)
                        .frame(width: geometry.size.width * Double(part.0) / Double(max(total, 1)))
                }
                Spacer(minLength: 0)
            }
            .background(.quaternary)
            .clipShape(Capsule())
        }
        .frame(height: 8)
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

struct NetworkPanel: View {
    let monitor: SystemMonitor
    @State private var range = TieredHistory.Range.minute

    var body: some View {
        let network = monitor.network
        PanelFrame(module: .network, subtitle: network?.interfaces.first?.name ?? "") {
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                BigFigure(text: "↓ \(Format.rate(network?.download ?? 0, style: .precise))")
                Text("↑ \(Format.rate(network?.upload ?? 0, style: .precise))")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            RangePicker(range: $range)
            InteractiveChart(
                series: [
                    series("download", loc("Download"), Palette.teal, .download),
                    series("upload", loc("Upload"), Palette.blue, .upload),
                ],
                mirrored: true,
                height: 70
            )
            Divider()
            if let network {
                PanelSection(title: loc("Interfaces"), caption: "↓ · ↑") {
                    ForEach(network.interfaces, id: \.name) { interface in
                        InfoRow(
                            title: interface.name,
                            value: "↓ \(Format.rate(interface.download, style: .precise))  ↑ \(Format.rate(interface.upload, style: .precise))"
                        )
                    }
                }
                Divider()
                InfoRow(
                    title: loc("This session"),
                    value: "↓ \(Format.bytes(Double(network.sessionReceived), style: .precise))  ↑ \(Format.bytes(Double(network.sessionSent), style: .precise))"
                )
            }
        }
    }

    private func series(_ id: String, _ title: String, _ color: Color, _ metric: Metric) -> ChartSeries {
        ChartSeries(id: id, title: title, color: color, points: monitor.points(metric, in: range)) {
            Format.rate($0, style: .precise)
        }
    }
}

struct BatteryPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        let battery = monitor.battery
        PanelFrame(
            module: .battery,
            subtitle: battery?.isOnAC == true ? loc("Power Adapter") : loc("On battery"),
            footerTitle: loc("Battery Settings…"),
            footerAction: {
                actions.openURL(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
            }
        ) {
            if let battery {
                summary(battery)
                Divider()
                details(battery)
            } else {
                Text(loc("This Mac has no battery"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private func summary(_ battery: BatterySample) -> some View {
        HStack(spacing: 14) {
            RingGauge(value: battery.charge, tint: battery.charge < 0.2 ? Palette.red : Palette.green, lineWidth: 8) {
                Text(Format.percent(battery.charge)).font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(timeText(battery)).font(.system(size: 16, weight: .semibold))
                Text(battery.isCharging ? loc("Charging") : loc("At current use"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeText(_ battery: BatterySample) -> String {
        guard let minutes = battery.minutesRemaining else { return loc("Calculating…") }
        let time = "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        return battery.isCharging ? loc("\(time) to full") : loc("\(time) left")
    }

    private func details(_ battery: BatterySample) -> some View {
        VStack(spacing: 6) {
            if let health = battery.health {
                InfoRow(title: loc("Health"), value: Format.percent(health))
            }
            if let cycles = battery.cycleCount {
                InfoRow(title: loc("Cycle count"), value: "\(cycles)")
            }
            InfoRow(title: loc("Power source"), value: battery.isOnAC ? loc("Power Adapter") : loc("Battery"))
            if let watts = battery.adapterWatts {
                InfoRow(title: loc("Adapter"), value: "\(watts) W")
            }
            if let celsius = battery
                .temperature
            {
                InfoRow(title: loc("Temperature"), value: Format.temperature(celsius))
            }
        }
    }
}

struct GPUPanel: View {
    let monitor: SystemMonitor
    @State private var range = TieredHistory.Range.minute

    var body: some View {
        let gpu = monitor.gpus.first
        PanelFrame(module: .gpu, subtitle: gpu?.name ?? "") {
            BigFigure(text: Format.percent(gpu?.device ?? 0))
            RangePicker(range: $range)
            InteractiveChart(
                series: [ChartSeries(
                    id: "gpu",
                    title: loc("GPU"),
                    color: Palette.purple,
                    points: monitor.points(.gpu, in: range),
                    format: { Format.percent($0, style: .precise) }
                )],
                domain: 0 ... 1
            )
            if let gpu {
                Divider()
                InfoRow(title: loc("Renderer"), value: Format.percent(gpu.renderer))
                InfoRow(title: loc("Tiler"), value: Format.percent(gpu.tiler))
            }
        }
    }
}

struct UptimePanel: View {
    var body: some View {
        let boot = SystemClock.bootTime() ?? .now
        PanelFrame(module: .uptime, subtitle: "") {
            BigFigure(text: CompactDuration.format(Date().timeIntervalSince(boot)))
            InfoRow(title: loc("Started"), value: boot.formatted(date: .abbreviated, time: .shortened))
        }
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
                ring(monitor.cpu?.total ?? 0, Palette.blue, loc("CPU"))
                ring(monitor.memory?.usedShare ?? 0, Palette.green, loc("Memory"))
                ring(1 - (monitor.volumes.first?.freeShare ?? 1), Palette.cyan, loc("Disk"))
            }
            .frame(maxWidth: .infinity)
            Divider()
            PanelSection(title: loc("Top processes"), caption: loc("% CPU")) {
                TopProcesses(processes: monitor.processes, sort: .cpu, tint: Palette.blue)
            }
        }
    }

    private func ring(_ value: Double, _ tint: Color, _ title: String) -> some View {
        VStack(spacing: 6) {
            RingGauge(value: value, tint: tint, lineWidth: 7) {
                Text(Format.percent(value)).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            .frame(width: 76, height: 76)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
