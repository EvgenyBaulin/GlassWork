import GlassWorkCore
import SwiftUI

extension ItemContent {
    static func aiUsage(
        _ reading: AIUsageReading?,
        at date: Date = Date(),
        options: [String: String] = [:]
    ) -> ItemContent {
        let choice = options.choice(AIUsageOption.window, default: AIUsageWindowChoice.both)
        let reading = AIUsageOption.chosenTool(options).map { reading?.only($0) } ?? reading
        guard let peak = reading?.peak(at: date, choice: choice) else {
            if let usage = reading?.tools.first(where: { $0.windows.isEmpty && $0.spend != nil && !$0.isUnreadable }),
               let spend = usage.spend
            {
                var item = ItemContent(figure: AISpendText.today(spend), template: "100.0")
                item.detail = "\(usage.tool.title) · \(AISpendText.summary(spend)) · \(loc("This Mac's sessions"))"
                return item
            }
            var item = ItemContent(figure: "—", template: "100%")
            item.isDimmed = true
            return item
        }
        if choice == .both, let pair = bothWindows(reading, at: date) {
            return pair
        }
        let share = peak.window.used(at: date)
        var item = ItemContent(
            figure: Format.percent(share),
            alert: share >= reading?.warnLevel ?? AIUsageReading.alertShare ? Palette.orange : nil,
            template: "100%"
        )
        item.glyph = .ring(share)
        let reset = peak.window.resetsAt.map { " · \(loc("resets \($0.timeText)"))" }
        item.detail = "\(peak.tool.title) \(Format.percent(share))\(reset ?? "")"
        return item
    }
}

extension ItemContent {
    /// Short text for one window in the menu bar, such as "5h 42%".
    static func aiWindowText(_ kind: AIWindow.Kind, share: Double) -> String {
        let label = kind == .week ? loc("wk") : loc("5h")
        return "\(label) \(Format.percent(share))"
    }

    /// Both limits on two short lines. Nil when the tools report only one of them.
    fileprivate static func bothWindows(_ reading: AIUsageReading?, at date: Date) -> ItemContent? {
        guard let reading,
              let five = reading.peak(at: date, kind: .fiveHour),
              let week = reading.peak(at: date, kind: .week)
        else { return nil }
        let fiveShare = five.window.used(at: date)
        let weekShare = week.window.used(at: date)
        let top = max(fiveShare, weekShare)
        var item = ItemContent(
            figure: aiWindowText(.fiveHour, share: fiveShare),
            alert: top >= reading.warnLevel ? Palette.orange : nil,
            template: "wk 100%"
        )
        item.secondLine = aiWindowText(.week, share: weekShare)
        item.glyph = .ring(top)
        item.detail = "\(five.tool.title) \(aiWindowText(.fiveHour, share: fiveShare)) · "
            + "\(week.tool.title) \(aiWindowText(.week, share: weekShare))"
        return item
    }
}

struct AIUsagePanel: View {
    let reading: AIUsageReading?
    let refreshMinutes: Int
    var now = Date()
    /// A read is in flight: the footer says so and the refresh button spins.
    var isUpdating = false
    var onRefresh: () -> Void = {}

    var body: some View {
        PanelFrame(module: .aiUsage, subtitle: loc("Local files")) {
            if let reading {
                if reading.tools.isEmpty {
                    PanelMessage(
                        symbol: "sparkle",
                        title: loc("No AI coding tools found"),
                        detail: loc("Tools show up here once they are installed.")
                    )
                    scanButton
                } else {
                    ForEach(reading.tools) { usage in
                        toolSection(usage)
                    }
                    if !reading.missing.isEmpty {
                        Text(loc("Not found on this Mac: \(reading.missing.map(\.title).joined(separator: " · "))"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    footer(reading)
                }
            } else {
                PanelMessage(symbol: "sparkle", title: loc("Reading usage…"))
            }
        }
    }

    private var scanButton: some View {
        Button(action: onRefresh) {
            HStack(spacing: 6) {
                if isUpdating {
                    ProgressView().controlSize(.small)
                }
                Text(isUpdating ? loc("Updating…") : loc("Scan again"))
            }
        }
        .disabled(isUpdating)
        .frame(maxWidth: .infinity)
    }

    private func footer(_ reading: AIUsageReading) -> some View {
        HStack {
            Text(isUpdating ? loc("Updating…") : footerText(reading))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if isUpdating {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else {
                RowIconButton(symbol: "arrow.clockwise", help: loc("Refresh now"), action: onRefresh)
            }
        }
    }

    private func footerText(_ reading: AIUsageReading) -> String {
        loc("Updated \(DeveloperText.relative(reading.readAt, to: now)) · refresh every \(refreshMinutes) min")
    }

    private func toolSection(_ usage: AIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AIToolBadge(tool: usage.tool)
                Text(usage.tool.title).font(.system(size: 13, weight: .semibold))
                Spacer()
                if let updated = usage.updatedAt {
                    Text(DeveloperText.relative(updated, to: now))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            if usage.isUnreadable {
                Text(loc("Can't read \(usage.tool.title) usage"))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.orange)
            } else if usage.windows.isEmpty, let spend = usage.spend {
                AISpendView(spend: spend)
            } else if usage.windows.isEmpty {
                Text(loc("No usage yet")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(usage.windows, id: \.kind) { window in
                    windowRow(window)
                }
                if let spend = usage.spend {
                    AISpendView(spend: spend)
                }
            }
        }
    }

    private func windowRow(_ window: AIWindow) -> some View {
        let share = window.used(at: now)
        let tint = share >= reading?.warnLevel ?? AIUsageReading.alertShare ? Palette.orange : Palette.green
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(AIWindowText.title(window.kind)).font(.system(size: 12))
                Spacer()
                Text(Format.percent(share))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            ThinBar(value: share, tint: tint, readout: AIWindowText.breakdown(window, now: now, tint: tint))
            if let caption = caption(window) {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func caption(_ window: AIWindow) -> String? {
        guard let reset = window.resetsAt, reset > now else { return nil }
        let left = reset.timeIntervalSince(now)
        if left < 86400 {
            let time = reset.timeText
            return loc("Resets in \(CompactDuration.format(left)) · \(time)")
        }
        return loc("Resets \(AIWindowText.resetDay(reset, from: now))")
    }
}

/// Words shared by the panel and the widget.
enum AIWindowText {
    static func title(_ kind: AIWindow.Kind) -> String {
        switch kind {
        case .fiveHour: loc("5-hour window")
        case .week: loc("This week")
        case .month: loc("This month")
        }
    }

    /// What the hover over a limit bar shows: used and left, and when the window resets.
    static func breakdown(_ window: AIWindow, now: Date, tint: Color) -> [HoverRow] {
        let used = window.used(at: now)
        var rows = [
            HoverRow(title: loc("Used"), value: Format.percent(used, style: .precise), color: tint),
            HoverRow(title: loc("Left"), value: Format.percent(1 - used, style: .precise)),
        ]
        if let reset = window.resetsAt, reset > now {
            rows.append(HoverRow(title: loc("Resets"), value: resetDay(reset, from: now)))
        }
        return rows
    }

    /// A weekday within the week, a date further out (a monthly plan resets weeks away).
    static func resetDay(_ date: Date, from now: Date) -> String {
        date.timeIntervalSince(now) < 6 * 86400
            ? date.formatted(.dateTime.weekday(.abbreviated).hour().minute().regional)
            : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
