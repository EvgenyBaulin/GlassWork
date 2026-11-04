import GlassWorkCore
import SwiftUI

/// A small drawing used instead of a sparkline.
public enum ItemGlyph: Equatable {
    case ring(Double)
    /// One dot per thing, up to five: filled first, then faint.
    case dots(filled: Int, faint: Int)
    /// The module has no history to draw, so the graph repeats its symbol.
    case symbol
    /// Level meter bars, each from 0 to 1.
    case bars([Double])
}

/// Keys in `ModuleSettings.options`.
public enum ModuleOption {
    public static let sensor = "sensor"
    public static let fanFigure = "figure"
    public static let eachFan = "eachFan"
    public static let maxWidth = "maxWidth"
    public static let defaultMaxWidth = 180.0
    public static let hideWhenIdle = "hideWhenIdle"
    public static let onlineLyrics = "onlineLyrics"
}

public extension SensorChoice {
    /// The temperature a module's options ask for. Anything unreadable means the default.
    static func shown(by options: [String: String]) -> SensorChoice {
        options[ModuleOption.sensor].flatMap(SensorChoice.init(rawValue:)) ?? .averageCPU
    }
}

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
    /// Replaces the module's symbol, for items whose glyph carries meaning.
    public var symbol: String?
    /// False for items that read fine as text alone.
    public var showsSymbol = true
    /// Drawn before the figure, except in the Labelled style, where the label says the same.
    public var prefix: String?
    /// Replaces the module's short label in the Labelled style.
    public var label: String?
    /// Drawn after the figure, in its own color.
    public var accent: ItemAccent?
    /// Graph points for modules that do not come from the system monitor.
    public var values: [Double]?
    /// Faded, because the data is old or the module is paused.
    public var isDimmed = false
    /// Drawn by the graph styles instead of a sparkline.
    public var glyph: ItemGlyph?
    /// How much of a variable symbol is drawn, from 0 to 1.
    public var symbolLevel: Double?
    /// Extra tooltip line.
    public var detail: String?
    /// Cover drawn in place of the symbol. The image is no longer a template then.
    public var artwork: Data?
    /// Long text is cut to this width instead of the item taking the template's width.
    public var figureWidth: CGFloat?
    /// Takes no room in the menu bar. The item stays, so it can come back by itself.
    public var isHidden = false

    /// Text for a raw metric value, used by tooltips.
    func format(_ value: Double) -> String {
        switch metric {
        case .cpu, .memory, .gpu: Format.percent(value)
        case .download, .upload, .diskRead, .diskWrite: Format.rate(value)
        case .temperature: Format.temperature(value)
        default: "\(Int(value))"
        }
    }

    /// How fast the fan glyph turns, from 0 (stopped) to 1.
    public var spin = 0.0

    static func content(
        _ module: ModuleID,
        monitor: SystemMonitor,
        style: NumberStyle,
        options: [String: String] = [:]
    ) -> ItemContent {
        switch module {
        case .overview: overview(monitor)
        case .cpu: percent(monitor.cpu?.total, metric: .cpu, style: style)
        case .memory: percent(monitor.memory?.usedShare, metric: .memory, style: style)
        case .gpu: percent(monitor.gpus.first?.device, metric: .gpu, style: style)
        case .disk: disk(monitor, style: style)
        case .network: network(monitor, style: style)
        case .battery: battery(monitor, style: style)
        case .sensors, .fans: thermal(module, monitor, options: options)
        case .uptime: uptime()
        case .timers, .stopwatch, .countdown, .worldClocks, .date, .sunMoon: everyday(module, monitor.everyday)
        case .calendar, .endsIn, .todos: agenda(module, monitor.agenda)
        case .deviceBatteries:
            ItemContent(
                figure: monitor.deviceBatteries.first.map { Format.percent($0.charge) } ?? "—",
                template: "100%"
            )
        case .keepAwake: ItemContent(figure: monitor.everyday.isKeepingAwake ? loc("On") : loc("Off"), template: "Off")
        case _ where ModuleID.developerCollected.contains(module): developer(module, monitor.developer)
        case .weather: weather(monitor.weather)
        case .rates: rates(monitor.rates)
        case .clipboard: clipboard(monitor.clipboard)
        case .nowPlaying: nowPlaying(monitor.nowPlaying, options: options)
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

    private static func thermal(
        _ module: ModuleID,
        _ monitor: SystemMonitor,
        options: [String: String]
    ) -> ItemContent {
        module == .fans ? fans(monitor, options: options) : sensors(monitor, options: options)
    }

    private static func sensors(_ monitor: SystemMonitor, options: [String: String]) -> ItemContent {
        let choice = SensorChoice.shown(by: options)
        let celsius = monitor.sensors?.celsius(for: choice)
        return ItemContent(
            figure: "\(choice.menuPrefix) \(celsius.map(Format.temperature) ?? "—")",
            metric: .temperature,
            domain: 20 ... 110,
            alert: (celsius ?? 0) >= 95 ? Palette.orange : nil,
            template: "\(choice.menuPrefix) 100°"
        )
    }

    private static func fans(_ monitor: SystemMonitor, options: [String: String]) -> ItemContent {
        let fans = monitor.sensors?.fans ?? []
        let eachFan = options[ModuleOption.fanFigure] == ModuleOption.eachFan && fans.count >= 2
        let average = monitor.sensors?.averageFanRPM
        let figure = if eachFan {
            loc("L \(Format.rpm(fans[0].rpm)) · R \(Format.rpm(fans[1].rpm))")
        } else {
            average.map { loc("\(Format.rpm($0)) rpm") } ?? "—"
        }
        var content = ItemContent(
            figure: figure,
            metric: .fan,
            // Max is the only state that earns the alert color.
            alert: fans.contains { $0.isManual && $0.target >= $0.maximum } ? Palette.orange : nil,
            template: eachFan ? loc("L \(Format.rpm(5800)) · R \(Format.rpm(5800))") : loc("\(Format.rpm(5800)) rpm")
        )
        let moving = fans.filter { $0.rpm > 0 }
        content.spin = moving.isEmpty ? 0 : max(moving.map(\.share).max() ?? 0, 0.1)
        return content
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

    private static func agenda(_ module: ModuleID, _ store: AgendaStore) -> ItemContent {
        let now = Date()
        switch module {
        case .todos:
            let count = TodoFilter.all.apply(to: store.todos, now: now).count
            return ItemContent(figure: store.remindersAccess == .granted ? "\(count)" : "—", template: "888")
        case .endsIn:
            let state = EndsInState(events: store.events, at: now)
            let remaining = state.current.first?.end.timeIntervalSince(now)
            let urgency = remaining.map(EndsInUrgency.init(remaining:))
            return ItemContent(
                figure: remaining?.clockText ?? "—",
                alert: urgency == .lastMinute ? Palette.red : urgency == .soon ? Palette.orange : nil,
                template: "8:88:88"
            )
        default:
            let next = EndsInState(events: store.events, at: now).next
            let text = next.map { $0.title.count > 16 ? "\($0.title.prefix(15))…" : $0.title }
            return ItemContent(figure: text ?? "—", template: "MMMMMMMMMMMM")
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
    private let options: [String: String]
    private let monitor: SystemMonitor

    public init(
        module: ModuleID,
        style: DisplayStyle,
        numbers: NumberStyle,
        options: [String: String] = [:],
        monitor: SystemMonitor
    ) {
        self.module = module
        self.style = style
        self.numbers = numbers
        self.options = options
        self.monitor = monitor
    }

    public var body: some View {
        let content = ItemContent.content(module, monitor: monitor, style: numbers, options: options)
        HStack(spacing: 4) {
            switch style {
            case .symbol: symbol(content)
            case .figure:
                if content.showsSymbol {
                    symbol(content)
                }
                figure(content)
            case .graph: symbol(content); graph(content)
            case .graphAndFigure: graph(content); figure(content)
            case .labelled: label(content); figure(content)
            }
        }
        .foregroundStyle(content.alert ?? .primary)
        .opacity(content.isDimmed ? 0.5 : 1)
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
        options: [String: String] = [:],
        monitor: SystemMonitor
    ) -> CGFloat {
        let content = ItemContent.content(module, monitor: monitor, style: numbers, options: options)
        let font = NSFont.monospacedDigitSystemFont(ofSize: content.secondLine == nil ? 12 : 9, weight: .medium)
        let text = content.figureWidth ?? ceil((content.template as NSString).size(withAttributes: [.font: font]).width)
        let padding: CGFloat = 8
        if content.isHidden {
            return 0
        }
        return switch style {
        case .symbol: 16 + padding
        case .figure: (content.showsSymbol ? 16 + 4 : 0) + text + padding
        case .graph: 16 + 4 + graphWidth + padding
        case .graphAndFigure: graphWidth + 4 + text + padding
        case .labelled: 8 + 4 + text + padding
        }
    }

    private static let graphWidth: CGFloat = 34

    private func symbol(_ content: ItemContent) -> some View {
        Image(systemName: content.symbol ?? module.symbol, variableValue: content.symbolLevel)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 16)
    }

    private func figure(_ content: ItemContent) -> some View {
        VStack(alignment: .leading, spacing: -1) {
            HStack(spacing: 4) {
                Text(content.text(for: style))
                if let accent = content.accent {
                    Text(accent.text).foregroundStyle(accent.color ?? .primary)
                }
            }
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
        switch content.glyph {
        case let .ring(value):
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 12, height: 12)
        case let .dots(filled, faint):
            HStack(spacing: 2) {
                ForEach(0 ..< min(filled + faint, 5), id: \.self) { index in
                    Circle().opacity(index < filled ? 1 : 0.3).frame(width: 5, height: 5)
                }
            }
        case .symbol:
            if style == .graphAndFigure {
                symbol(content)
            }
        case let .bars(levels):
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule().frame(width: 3, height: 3 + 11 * level)
                }
            }
        case nil:
            if let values = content.graphValues(monitor) {
                Sparkline(
                    values: values,
                    domain: content.domain,
                    color: content.accent?.color ?? content.alert ?? .primary
                )
                .frame(width: Self.graphWidth, height: 16)
            }
        }
    }

    private func label(_ content: ItemContent) -> some View {
        let text = content.label ?? module.shortLabel
        let isLong = text.count > 3
        return VStack(spacing: isLong ? -1 : -1.5) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
            }
        }
        .font(.system(size: isLong ? 5 : 6.5, weight: .bold))
        .frame(width: 8)
    }
}
