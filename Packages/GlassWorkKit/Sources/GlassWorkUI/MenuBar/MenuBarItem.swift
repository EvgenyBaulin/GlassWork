import GlassWorkCore
import SwiftUI

/// What a module shows in the menu bar right now.
@MainActor
public struct ItemContent {
    public var figure: String
    public var secondLine: String?
    public var metric: Metric?
    public var domain: ClosedRange<Double>?
    /// Set only for alerts; items are monochrome otherwise.
    public var alert: Color?
    /// Longest expected text, so the item keeps one width as figures change.
    public var template: String

    /// Text for a raw metric value, used by tooltips.
    func format(_ value: Double) -> String {
        switch metric {
        case .cpu, .memory, .gpu: Format.percent(value)
        case .download, .upload, .diskRead, .diskWrite: Format.rate(value)
        case .temperature: Format.temperature(value)
        default: "\(Int(value))"
        }
    }

    static func content(_ module: ModuleID, monitor: SystemMonitor, style: NumberStyle) -> ItemContent {
        switch module {
        case .overview: overview(monitor)
        case .cpu: percent(monitor.cpu?.total, metric: .cpu, style: style)
        case .memory: percent(monitor.memory?.usedShare, metric: .memory, style: style)
        case .gpu: percent(monitor.gpus.first?.device, metric: .gpu, style: style)
        case .disk: disk(monitor, style: style)
        case .network: network(monitor, style: style)
        case .battery: battery(monitor, style: style)
        case .sensors: sensors(monitor)
        case .uptime: uptime()
        case .timers, .stopwatch, .countdown, .worldClocks, .date, .sunMoon: everyday(module, monitor.everyday)
        case .keepAwake: ItemContent(figure: monitor.everyday.isKeepingAwake ? loc("On") : loc("Off"), template: "Off")
        default: ItemContent(figure: "—", template: "—")
        }
    }

    init(
        figure: String,
        secondLine: String? = nil,
        metric: Metric? = nil,
        domain: ClosedRange<Double>? = nil,
        alert: Color? = nil,
        template: String
    ) {
        self.figure = figure
        self.secondLine = secondLine
        self.metric = metric
        self.domain = domain
        self.alert = alert
        self.template = template
    }

    private static func percent(_ value: Double?, metric: Metric, style: NumberStyle) -> ItemContent {
        ItemContent(
            figure: value.map { Format.percent($0, style: style) } ?? "—",
            metric: metric,
            domain: 0 ... 1,
            template: style == .compact ? "100%" : "100.0%"
        )
    }

    private static func overview(_ monitor: SystemMonitor) -> ItemContent {
        let cpu = Format.percent(monitor.cpu?.total ?? 0)
        let memory = Format.percent(monitor.memory?.usedShare ?? 0)
        return ItemContent(figure: "\(cpu) \(memory)", metric: .cpu, domain: 0 ... 1, template: "100% 100%")
    }

    private static func disk(_ monitor: SystemMonitor, style: NumberStyle) -> ItemContent {
        let volume = monitor.volumes.first
        let isLow = (volume?.freeShare ?? 1) < 0.1
        return ItemContent(
            figure: volume.map { Format.bytes(Double($0.free), style: style) } ?? "—",
            metric: .diskRead,
            alert: isLow ? Palette.orange : nil,
            template: style == .compact ? "999G" : "999.9 GB"
        )
    }

    private static func network(_ monitor: SystemMonitor, style: NumberStyle) -> ItemContent {
        ItemContent(
            figure: "↓ \(Format.rate(monitor.network?.download ?? 0, style: style))",
            secondLine: "↑ \(Format.rate(monitor.network?.upload ?? 0, style: style))",
            metric: .download,
            template: style == .compact ? "↓ 999M/s" : "↓ 999.9 MB/s"
        )
    }

    private static func battery(_ monitor: SystemMonitor, style: NumberStyle) -> ItemContent {
        let battery = monitor.battery
        let isLow = (battery?.charge ?? 1) <= 0.1 && battery?.isCharging == false
        return ItemContent(
            figure: battery.map { Format.percent($0.charge, style: style) } ?? "—",
            alert: isLow ? Palette.red : nil,
            template: "100%"
        )
    }

    private static func sensors(_ monitor: SystemMonitor) -> ItemContent {
        let celsius = monitor.sensors?.averageCPU
        return ItemContent(
            figure: celsius.map(Format.temperature) ?? "—",
            metric: .temperature,
            domain: 20 ... 110,
            alert: (celsius ?? 0) >= 95 ? Palette.orange : nil,
            template: "100°C"
        )
    }

    private static func everyday(_ module: ModuleID, _ store: EverydayStore) -> ItemContent {
        let now = Date()
        switch module {
        case .timers:
            let next = store.data.timers.map { $0.remaining(at: now) }.min()
            return ItemContent(figure: next?.clockText ?? "—", template: "88:88")
        case .stopwatch:
            return ItemContent(figure: store.data.stopwatch.elapsed(at: now).clockText, template: "88:88:88")
        case .countdown:
            let next = store.data.sortedDates(from: now).first
            return ItemContent(figure: next.map { loc("\($0.daysLeft(from: now)) d") } ?? "—", template: "888 d")
        case .worldClocks:
            return ItemContent(figure: firstCityTime(store), template: "88:88 PM")
        case .date:
            return ItemContent(figure: now.formatted(.dateTime.weekday().day().month()), template: "Wed, 28 Sep")
        default:
            let times = Astronomy.sunTimes(on: now, latitude: 55.75, longitude: 37.62)
            let next = [times.sunrise, times.sunset].compactMap(\.self).first { $0 > now }
            return ItemContent(figure: next?.formatted(date: .omitted, time: .shortened) ?? "—", template: "88:88 PM")
        }
    }

    private static func firstCityTime(_ store: EverydayStore) -> String {
        guard let city = store.data.cities.first else { return "—" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: city.timeZone) ?? .current
        return Date().formatted(style)
    }

    private static func uptime() -> ItemContent {
        let boot = SystemClock.bootTime() ?? .now
        return ItemContent(figure: CompactDuration.format(Date().timeIntervalSince(boot)), template: "99d 23h")
    }
}

/// A module in one of the five display styles, at the menu bar's 24 pt height.
public struct MenuBarItemView: View {
    private let module: ModuleID
    private let style: DisplayStyle
    private let numbers: NumberStyle
    private let monitor: SystemMonitor

    public init(module: ModuleID, style: DisplayStyle, numbers: NumberStyle, monitor: SystemMonitor) {
        self.module = module
        self.style = style
        self.numbers = numbers
        self.monitor = monitor
    }

    public var body: some View {
        let content = ItemContent.content(module, monitor: monitor, style: numbers)
        HStack(spacing: 4) {
            switch style {
            case .symbol: symbol
            case .figure: symbol; figure(content)
            case .graph: symbol; graph(content)
            case .graphAndFigure: graph(content); figure(content)
            case .labelled: label; figure(content)
            }
        }
        .foregroundStyle(content.alert ?? .primary)
        .frame(height: 22)
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
    }

    /// Fixed item width, so the menu bar never jiggles as figures change.
    @MainActor
    public static func width(
        module: ModuleID,
        style: DisplayStyle,
        numbers: NumberStyle,
        monitor: SystemMonitor
    ) -> CGFloat {
        let content = ItemContent.content(module, monitor: monitor, style: numbers)
        let font = NSFont.monospacedDigitSystemFont(ofSize: content.secondLine == nil ? 12 : 9, weight: .medium)
        let text = ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
        let padding: CGFloat = 8
        return switch style {
        case .symbol: 16 + padding
        case .figure: 16 + 4 + text + padding
        case .graph: 16 + 4 + graphWidth + padding
        case .graphAndFigure: graphWidth + 4 + text + padding
        case .labelled: 8 + 4 + text + padding
        }
    }

    private static let graphWidth: CGFloat = 34

    private var symbol: some View {
        Image(systemName: module.symbol)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)
    }

    private func figure(_ content: ItemContent) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            Text(content.figure)
            if let second = content.secondLine {
                Text(second)
            }
        }
        .font(.system(size: content.secondLine == nil ? 12 : 9, weight: .medium))
        .monospacedDigit()
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func graph(_ content: ItemContent) -> some View {
        if let metric = content.metric {
            Sparkline(
                values: monitor.points(metric, in: .minute).suffix(30).map(\.value),
                domain: content.domain,
                color: content.alert ?? .primary
            )
            .frame(width: Self.graphWidth, height: 16)
        }
    }

    private var label: some View {
        VStack(spacing: -1.5) {
            ForEach(Array(module.shortLabel.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
            }
        }
        .font(.system(size: 6.5, weight: .bold))
        .frame(width: 8)
    }
}
