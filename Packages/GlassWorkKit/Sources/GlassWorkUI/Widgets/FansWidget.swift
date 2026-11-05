import GlassWorkCore
import SwiftUI
import WidgetKit

/// Both fans, their average and control from the desktop. A click goes App Intent → app → `FanControlModel`.
struct FansWidget: View {
    let context: TimeContext
    /// Starts the chart as if the cursor were on it, for tests of the hover state.
    var chartHover: Date?
    @Environment(\.widgetRenderingMode) fileprivate var renderingMode

    private var fans: [FanReading] {
        context.snapshot.sensors?.fans ?? []
    }

    /// Without state from the app nothing can be controlled, which is the safe reading.
    fileprivate var state: WidgetFanState {
        context.snapshot.fans ?? WidgetFanState()
    }

    private var average: Double {
        context.snapshot.sensors?.averageFanRPM ?? 0
    }

    fileprivate var isMax: Bool {
        state.mode == .max
    }

    private var valueTint: Color {
        isMax ? Palette.orange : .primary
    }

    fileprivate var symbol: String {
        ModuleID.fans.symbol
    }

    var body: some View {
        if context.snapshot.sensors == nil || context.snapshot.fans == nil {
            WidgetChecking(symbol: symbol, tint: Palette.cyan)
        } else if fans.isEmpty {
            WidgetEmptyState(
                symbol: "fan.slash",
                title: loc("No fans on this Mac"),
                detail: context.size == .small ? nil : loc("Fanless Macs have nothing to show here.")
            )
        } else {
            switch context.size {
            case .small: small
            case .medium: medium
            case .large: large
            case .extraLarge: extraLarge
            }
        }
    }

    private var header: some View {
        HStack {
            WidgetHeader(title: loc("Fans"), symbol: symbol, tint: isMax ? Palette.orange : Palette.cyan)
            Spacer()
            Text(modeNote).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var modeNote: String {
        state.mode == .curve ? state.selectedPreset?.title ?? state.mode.title : state.mode.title
    }

    private var figure: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Format.groupedRPM(average))
                .font(.widgetFigure(30))
                .monospacedDigit()
                .foregroundStyle(valueTint)
                .widgetAccentable()
            Text(loc("rpm avg")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var perFan: some View {
        Text(fans.map { "\(shortName($0)) \(Format.rpm($0.rpm))" }.joined(separator: " · "))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// The full name does not fit next to the speed in the medium size.
    private func rowTitle(_ fan: FanReading) -> String {
        guard fans.count == 2 else { return fan.title(among: fans.count) }
        return fan.id == 0 ? loc("Left") : loc("Right")
    }

    private func shortName(_ fan: FanReading) -> String {
        fans.count == 2 ? (fan.id == 0 ? loc("L") : loc("R")) : "\(fan.id + 1)"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            figure
            perFan
            Spacer(minLength: 0)
            if state.canControl {
                maxButton
            } else {
                Label(controlTitle, systemImage: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                figure
                perFan
                Spacer(minLength: 0)
                Text(footnote).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 7) {
                if let message = cardMessage {
                    messageCard(message)
                } else {
                    if state.mode == .curve {
                        presetSwitcher
                    }
                    ForEach(fans) { row($0) }
                    Spacer(minLength: 0)
                }
                maxButton
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetTitle(title: loc("Fans"), symbol: symbol, tint: Palette.cyan, note: modeNote)
            leftColumn(chartHeight: chartHeight(base: 124))
        }
    }

    private var extraLarge: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 9) {
                WidgetTitle(title: loc("Fans"), symbol: symbol, tint: Palette.cyan, note: modeNote)
                leftColumn(chartHeight: chartHeight(base: 124))
            }
            .frame(width: 350)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if state.mode == .curve {
                    curveSection(height: 120)
                } else {
                    customSection
                }
                sensors
                Spacer(minLength: 0)
            }
        }
    }

    /// What is left once a message or the curve presets took their place.
    private func chartHeight(base: CGFloat) -> CGFloat {
        let presets: CGFloat = context.size == .large && state.mode == .curve ? 36 : 0
        return base - presets - (cardMessage == nil ? 0 : 62)
    }

    @ViewBuilder
    private func leftColumn(chartHeight: CGFloat) -> some View {
        HStack(spacing: 8) {
            ForEach(fans.prefix(2)) { tile($0) }
        }
        HStack {
            Text(loc("avg \(Format.groupedRPM(average)) rpm"))
            Spacer()
            if let celsius = context.snapshot.sensors?.averageCPU {
                Text(loc("CPU avg \(Format.temperature(celsius))"))
            }
        }
        .font(.system(size: 12, weight: .semibold))
        if context.size == .large, state.mode == .curve {
            curveSection(height: chartHeight)
        } else {
            history(height: chartHeight)
        }
        if let message = cardMessage {
            messageCard(message)
        }
        if state.mode == .curve, context.size == .large {
            presetSwitcher
        }
        HStack(spacing: 8) {
            // Max has its own button right here, and a second one in the control would say the same thing.
            modeSwitcher(FanMode.allCases.filter { $0 != .max })
            maxButton.frame(width: 84)
        }
        Spacer(minLength: 0)
        Text(footnote).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
    }

    private func tile(_ fan: FanReading) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(fan.title(among: fans.count), systemImage: symbol)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Format.groupedRPM(fan.rpm))
                    .font(.widgetFigure(18))
                    .monospacedDigit()
                    .foregroundStyle(valueTint)
                Text(loc("rpm")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ThinBar(value: fan.share, tint: isMax ? Palette.orange : Palette.cyan)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }

    private func row(_ fan: FanReading) -> some View {
        HStack {
            Label(rowTitle(fan), systemImage: symbol)
                .font(.system(size: 12))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(loc("\(Format.groupedRPM(fan.rpm)) rpm"))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func history(height: CGFloat) -> some View {
        let points = context.snapshot.fanHistory ?? [:]
        let series = fans.prefix(2).enumerated().map { index, fan in
            ChartSeries(
                id: "fan\(fan.id)",
                title: fan.title(among: fans.count),
                color: index == 0 ? Palette.cyan : Palette.teal,
                points: points[fan.id] ?? [],
                format: { loc("\(Format.groupedRPM($0)) rpm") }
            )
        }
        return VStack(alignment: .leading, spacing: 3) {
            Text(loc("RPM · last 10 min")).font(.system(size: 10)).foregroundStyle(.secondary)
            InteractiveChart(
                series: series,
                domain: ItemContent.padded(series.flatMap(\.points).map(\.value)),
                height: height,
                initialHover: chartHover
            )
        }
    }

    private func curveSection(height: CGFloat) -> some View {
        let fan = fans.first
        let range = (fan?.minimum ?? 0) ... max(fan?.maximum ?? 1, (fan?.minimum ?? 0) + 1)
        let celsius = context.snapshot.sensors?.celsius(for: state.sensor)
        return FanCurveChart(
            curve: FanCurve(points: state.curve),
            rpmRange: range,
            live: celsius.map { FanCurveChart.Live(celsius: $0, rpm: average) },
            height: height
        )
        .widgetAccentable()
    }

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetSection(title: loc("Custom"))
            HStack {
                stepButton("minus", to: target - Self.step)
                Spacer()
                VStack(spacing: 0) {
                    Text(Format.groupedRPM(target)).font(.widgetFigure(22)).monospacedDigit()
                    Text(loc("rpm target")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                stepButton("plus", to: target + Self.step)
            }
            HStack(spacing: 6) {
                ForEach(chips, id: \.title) { chip in
                    WidgetActionButton(action: .setFanCustom(rpm: chip.rpm), isEnabled: state.canControl) {
                        Text(verbatim: chip.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: .capsule)
                    }
                }
            }
        }
    }

    private static let step = 200.0

    /// The target the buttons step from: the saved one, or what the fans do now on a first visit.
    private var target: Double {
        state.customRPM > 0 ? state.customRPM : average
    }

    private var chips: [(title: String, rpm: Double)] {
        let low = fans.map(\.minimum).max() ?? 0
        let high = fans.map(\.maximum).min() ?? 0
        guard high > low else { return [] }
        return [(loc("Quiet"), 0.2), (loc("Balanced"), 0.5), (loc("Cool"), 0.8)].map { title, share in
            let rpm = ((low + (high - low) * share) / 100).rounded() * 100
            return ("\(title) \(Format.groupedRPM(rpm))", rpm)
        }
    }

    private func stepButton(_ symbol: String, to rpm: Double) -> some View {
        WidgetActionButton(action: .setFanCustom(rpm: rpm), isEnabled: state.canControl) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 30)
                .background(.quaternary, in: .circle)
        }
    }

    private var sensors: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetSection(title: loc("Sensors"))
            ForEach(sensorRows, id: \.title) { row in
                HStack(spacing: 8) {
                    Text(row.title).font(.system(size: 11)).frame(width: 66, alignment: .leading).lineLimit(1)
                    ThinBar(value: row.celsius / 100, tint: row.celsius >= 90 ? Palette.red : Palette.green)
                    Text(Format.degrees(row.celsius))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }

    private var sensorRows: [(title: String, celsius: Double)] {
        guard let sample = context.snapshot.sensors else { return [] }
        let rows: [(String, Double?)] = [
            (loc("CPU avg"), sample.averageCPU),
            (loc("GPU avg"), sample.averageGPU),
            (loc("SoC avg"), sample.averageSoC),
            (loc("SSD"), sample.average(of: [.storage])),
            (loc("Battery"), sample.average(of: [.battery])),
            (loc("Ambient"), sample.average(of: [.ambient])),
        ]
        return rows.compactMap { title, value in value.map { (title, $0) } }
    }
}

private struct FanSegment {
    let title: String
    let action: WidgetCommand.Action
    let isOn: Bool
}

private struct FanMessage {
    let symbol: String
    let title: String
    let detail: String
}

/// The controls and the messages about them.
private extension FansWidget {
    func modeSwitcher(_ modes: [FanMode]) -> some View {
        segments(modes.map { FanSegment(title: $0.title, action: .setFanMode($0), isOn: $0 == state.mode) })
    }

    var presetSwitcher: some View {
        segments(state.presets.prefix(3).map { preset in
            FanSegment(
                title: preset.title,
                action: .selectFanPreset(preset.id),
                isOn: preset.id == state.selectedPresetID
            )
        })
    }

    func segments(_ items: [FanSegment]) -> some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.title) { item in
                WidgetActionButton(action: item.action, isEnabled: state.canControl) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(fill(isOn: item.isOn), in: .rect(cornerRadius: 7))
                        .contentShape(.rect)
                }
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 9))
    }

    func fill(isOn: Bool) -> AnyShapeStyle {
        guard isOn else { return AnyShapeStyle(.clear) }
        return isMax && renderingMode == .fullColor ? AnyShapeStyle(Palette.orange) : AnyShapeStyle(.quaternary)
    }

    var maxButton: some View {
        WidgetActionButton(action: .toggleFanMax, isEnabled: state.canControl) {
            Label(loc("Max"), systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .widgetSolid(isMax ? Palette.orange : nil, in: .capsule)
                .contentShape(.capsule)
        }
    }

    var footnote: String {
        switch state.mode {
        case .auto: loc("Auto · macOS fan curve")
        case .curve: loc("Back to Auto on quit, sleep or crash")
        case .max: loc("Max until you switch back")
        case .custom: loc("Custom until you switch back")
        }
    }

    var controlTitle: String {
        switch state.control {
        case .ready: ""
        case .off: loc("Control is off")
        case .notInstalled: loc("Service not installed")
        case .needsApproval: loc("Service needs approval")
        }
    }

    var controlDetail: String {
        switch state.control {
        case .ready: ""
        case .off: loc("Turn on fan control in GlassWork Settings.")
        case .notInstalled: loc("Install the fan service in GlassWork Settings. Readings work without it.")
        case .needsApproval: loc("Allow the fan service in System Settings › Login Items.")
        }
    }

    /// A notice comes first: it explains a change the user did not ask for.
    var cardMessage: FanMessage? {
        switch state.notice {
        case let .failsafeMax(celsius):
            FanMessage(
                symbol: "exclamationmark.triangle.fill",
                title: loc("CPU \(Format.temperature(celsius)) — switched to Max"),
                detail: loc("Max stays on until you pick a mode.")
            )
        case .returnedToAuto:
            FanMessage(
                symbol: "info.circle.fill",
                title: loc("Back to Auto"),
                detail: loc("Fan control stopped, so macOS took over again.")
            )
        case nil:
            state.canControl ? nil : FanMessage(symbol: "lock.fill", title: controlTitle, detail: controlDetail)
        }
    }

    func messageCard(_ message: FanMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(message.title, systemImage: message.symbol)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(message.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}

extension WidgetFanState.Preset {
    /// Built-in names are translated; a user's own name is shown as it was typed.
    var title: String {
        FanPreset.builtIn.first { $0.id == id }?.title ?? name
    }
}
