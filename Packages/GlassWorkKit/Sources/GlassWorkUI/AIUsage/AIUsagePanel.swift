import GlassWorkCore
import SwiftUI

extension ItemContent {
    static func aiUsage(_ reading: AIUsageReading?, at date: Date = Date()) -> ItemContent {
        guard let peak = reading?.peak(at: date) else {
            var item = ItemContent(figure: "—", template: "100%")
            item.isFaint = true
            return item
        }
        let share = peak.window.used(at: date)
        var item = ItemContent(
            figure: Format.percent(share),
            alert: share >= AIUsageReading.alertShare ? Palette.orange : nil,
            template: "100%"
        )
        item.glyph = .ring(share)
        let reset = peak.window.resetsAt.map { " · \(loc("resets \($0.formatted(date: .omitted, time: .shortened))"))" }
        item.detail = "\(peak.tool.title) \(Format.percent(share))\(reset ?? "")"
        return item
    }
}

struct AIUsagePanel: View {
    let reading: AIUsageReading?
    let refreshMinutes: Int
    var now = Date()
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

    private func footer(_ reading: AIUsageReading) -> some View {
        HStack {
            Text(footerText(reading)).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            RowIconButton(symbol: "arrow.clockwise", help: loc("Refresh now"), action: onRefresh)
        }
    }

    private func footerText(_ reading: AIUsageReading) -> String {
        loc("Updated \(DeveloperText.relative(reading.readAt, to: now)) · refresh every \(refreshMinutes) min")
    }

    private func toolSection(_ usage: AIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                badge(usage.tool)
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
            } else if usage.windows.isEmpty {
                Text(loc("No usage yet")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ForEach(usage.windows, id: \.kind) { window in
                    windowRow(window)
                }
            }
        }
    }

    private func badge(_ tool: AITool) -> some View {
        Text(verbatim: tool.initial)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(tint(of: tool).gradient, in: .rect(cornerRadius: 6))
    }

    private func tint(of tool: AITool) -> Color {
        switch tool {
        case .claudeCode: Palette.orange
        case .codex: Palette.gray
        case .geminiCLI: Palette.blue
        case .openCode: Palette.teal
        case .copilotCLI: Palette.purple
        case .droid: Palette.green
        }
    }

    private func windowRow(_ window: AIWindow) -> some View {
        let share = window.used(at: now)
        let tint = share >= AIUsageReading.alertShare ? Palette.orange : Palette.green
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.kind == .fiveHour ? loc("5-hour window") : loc("This week")).font(.system(size: 12))
                Spacer()
                Text(Format.percent(share))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            ThinBar(value: share, tint: tint).help(Format.percent(share, style: .precise))
            if let caption = caption(window) {
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func caption(_ window: AIWindow) -> String? {
        guard let reset = window.resetsAt, reset > now else { return nil }
        let left = reset.timeIntervalSince(now)
        if left < 86400 {
            let time = reset.formatted(date: .omitted, time: .shortened)
            return loc("Resets in \(CompactDuration.format(left)) · \(time)")
        }
        return loc("Resets \(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
    }
}
