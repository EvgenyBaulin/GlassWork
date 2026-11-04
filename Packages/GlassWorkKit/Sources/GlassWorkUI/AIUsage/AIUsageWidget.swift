import GlassWorkCore
import SwiftUI
import WidgetKit

extension AITool {
    var tint: Color {
        switch self {
        case .claudeCode: Palette.orange
        case .codex: Palette.gray
        case .geminiCLI: Palette.blue
        case .openCode: Palette.teal
        case .copilotCLI: Palette.purple
        case .droid: Palette.green
        }
    }
}

/// Letter tile of a tool. There are no logos on purpose.
struct AIToolBadge: View {
    let tool: AITool
    var size: CGFloat = 22

    var body: some View {
        Text(verbatim: tool.initial)
            .font(.system(size: size * 0.55, weight: .bold))
            .frame(width: size, height: size)
            .widgetSolid(tool.tint, in: .rect(cornerRadius: size * 0.27))
    }
}

/// How close each tool is to its limits, from the tools' own local files.
struct AIUsageWidget: View {
    let context: TimeContext

    private var now: Date {
        context.now
    }

    /// Tools with numbers first, so a tool that was only detected never pushes a real one out of the widget.
    private var tools: [AIToolUsage] {
        let usage = context.snapshot.aiUsage?.tools ?? []
        return usage.filter { !$0.windows.isEmpty } + usage.filter(\.windows.isEmpty)
    }

    private var header: some View {
        WidgetHeader(title: ModuleID.aiUsage.title, symbol: "sparkle", tint: Palette.orange)
    }

    var body: some View {
        if context.snapshot.aiUsage == nil {
            WidgetChecking(symbol: "sparkle", tint: Palette.orange)
        } else if let first = tools.first {
            switch context.size {
            case .small: small(first)
            case .medium:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(tools.prefix(2)) { column($0) }
                    }
                    Spacer(minLength: 0)
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    header
                    ForEach(tools.prefix(3)) { section($0) }
                    Spacer(minLength: 0)
                    Text(loc("\(tools.count) of \(AITool.allCases.count) supported tools found"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        header
                        ForEach(tools.prefix(3)) { section($0) }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    sideColumn
                }
            }
        } else {
            WidgetEmptyState(
                symbol: "sparkle",
                title: loc("No tools found"),
                detail: context.size == .small ? nil : loc("Usage appears once a tool writes its files on this Mac."),
                tint: Palette.orange
            )
        }
    }

    private func small(_ usage: AIToolUsage) -> some View {
        let window = usage.peak(at: now)
        let share = window?.used(at: now) ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            header
            HStack(spacing: 5) {
                AIToolBadge(tool: usage.tool, size: 16)
                Text(usage.tool.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            Text(Format.percent(share)).font(.widgetFigure(30)).foregroundStyle(tint(share)).widgetAccentable()
            Text(window.map(windowTitle) ?? loc("No usage yet")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ThinBar(value: share, tint: tint(share))
            if let window, let reset = resetText(window) {
                Text(reset).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private func column(_ usage: AIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                AIToolBadge(tool: usage.tool, size: 16)
                Text(usage.tool.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
                activity(usage)
            }
            windows(usage, showsResets: false)
            if let window = usage.peak(at: now), let reset = resetText(window) {
                Text(reset).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ usage: AIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                AIToolBadge(tool: usage.tool)
                Text(usage.tool.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                activity(usage)
            }
            windows(usage, showsResets: true)
        }
    }

    @ViewBuilder
    private func windows(_ usage: AIToolUsage, showsResets: Bool) -> some View {
        if usage.isUnreadable {
            Text(loc("Can't read \(usage.tool.title) usage"))
                .font(.system(size: 11))
                .foregroundStyle(Palette.orange)
                .lineLimit(1)
        } else if usage.windows.isEmpty {
            Text(loc("No usage yet")).font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ForEach(usage.windows, id: \.kind) { window in
                row(window, showsReset: showsResets)
            }
        }
    }

    private func row(_ window: AIWindow, showsReset: Bool) -> some View {
        let share = window.used(at: now)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(windowTitle(window)).font(.system(size: 11)).lineLimit(1)
                if showsReset, let reset = resetText(window) {
                    Text(reset).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                Text(Format.percent(share))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint(share))
            }
            ThinBar(value: share, tint: tint(share))
        }
    }

    @ViewBuilder
    private func activity(_ usage: AIToolUsage) -> some View {
        if let updated = usage.updatedAt {
            Text(DeveloperText.relative(updated, to: now))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetSection(title: loc("Next resets"))
            ForEach(nextResets, id: \.title) { item in
                WidgetFact(title: item.title, value: item.value)
            }
            Divider()
            WidgetSection(title: loc("Not found on this Mac"))
            ForEach(context.snapshot.aiUsage?.missing ?? []) { tool in
                HStack {
                    Image(systemName: "circle").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(tool.title).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(loc("Only counters and limits are read, never prompts or code."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    private var nextResets: [(title: String, value: String)] {
        tools.compactMap { usage in
            let soonest = usage.windows.compactMap(\.resetsAt).filter { $0 > now }.min()
            return soonest.map { (usage.tool.title, resetTime($0)) }
        }
    }

    private func windowTitle(_ window: AIWindow) -> String {
        window.kind == .fiveHour ? loc("5-hour window") : loc("This week")
    }

    private func resetText(_ window: AIWindow) -> String? {
        guard let reset = window.resetsAt, reset > now else { return nil }
        let time = resetTime(reset)
        return window.used(at: now) >= 1 ? loc("Limit reached · back \(time)") : loc("Resets \(time)")
    }

    private func resetTime(_ date: Date) -> String {
        date.timeIntervalSince(now) < 86400
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private func tint(_ share: Double) -> Color {
        if share >= AIUsageReading.alertShare {
            return Palette.red
        }
        return share >= 0.7 ? Palette.orange : Palette.green
    }
}
