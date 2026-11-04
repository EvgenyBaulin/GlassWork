import GlassWorkCore
import SwiftUI
import WidgetKit

/// Read and write speed across all disks.
struct DiskActivityWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var header: some View {
        WidgetHeader(title: loc("Disk Activity"), symbol: "internaldrive", tint: Palette.cyan)
    }

    var body: some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                header
                speed("arrow.down", read, tint: Palette.cyan, size: 18)
                speed("arrow.up", write, tint: Palette.blue, size: 18)
                Spacer(minLength: 0)
                chart(context.snapshot.diskMinute, height: 34, barWidth: 2.5)
            }
        case .medium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    labelled(loc("Read"), "arrow.down", read, tint: Palette.cyan, size: 20)
                    labelled(loc("Write"), "arrow.up", write, tint: Palette.blue, size: 20)
                    Spacer(minLength: 0)
                }
                chart(context.snapshot.diskMinute, height: 118, barWidth: 3.5)
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                title
                speeds
                chart(context.snapshot.diskLonger, height: 160, barWidth: 7)
                axis
                Divider()
                peaks
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    title
                    speeds
                    chart(context.snapshot.diskLonger, height: 240, barWidth: 7)
                    axis
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    WidgetSection(title: loc("Disks"))
                    ForEach(context.snapshot.volumes.prefix(4)) { volume in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(volume.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text(loc("\(Format.bytes(Double(volume.free), style: .precise)) free"))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            ThinBar(value: 1 - volume.freeShare, tint: Palette.cyan)
                        }
                    }
                    Divider()
                    peaks
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var title: some View {
        WidgetTitle(title: loc("Disk Activity"), symbol: "internaldrive", tint: Palette.cyan, note: loc("All disks"))
    }

    private var read: Double {
        context.snapshot.diskActivity?.read ?? 0
    }

    private var write: Double {
        context.snapshot.diskActivity?.write ?? 0
    }

    private var speeds: some View {
        HStack(spacing: 24) {
            labelled(loc("Read"), "arrow.down", read, tint: Palette.cyan, size: 22)
            labelled(loc("Write"), "arrow.up", write, tint: Palette.blue, size: 22)
        }
    }

    private func labelled(_ title: String, _ symbol: String, _ value: Double, tint: Color, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetSection(title: title)
            speed(symbol, value, tint: tint, size: size)
        }
    }

    private func speed(_ symbol: String, _ value: Double, tint: Color, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol).font(.system(size: size * 0.6, weight: .bold)).foregroundStyle(tint)
                .widgetAccentable()
            Text(Format.rate(value, style: .precise))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func chart(_ history: WidgetDiskHistory?, height: CGFloat, barWidth: CGFloat) -> some View {
        InteractiveChart(
            series: [
                ChartSeries(
                    id: "read",
                    title: loc("Read"),
                    color: Palette.cyan,
                    points: history?.read ?? [],
                    format: { Format.rate($0, style: .precise) }
                ),
                ChartSeries(
                    id: "write",
                    title: loc("Write"),
                    color: Palette.blue,
                    points: history?.write ?? [],
                    format: { Format.rate($0, style: .precise) }
                ),
            ],
            mirrored: true,
            height: height,
            style: .bars(width: barWidth),
            initialHover: chartHover
        )
    }

    private var axis: some View {
        HStack {
            Text(loc("5 min ago"))
            Spacer()
            Text(loc("now"))
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private var peaks: some View {
        let history = context.snapshot.diskLonger
        WidgetFact(
            title: loc("Peak read"),
            value: Format.rate(history?.read.map(\.value).max() ?? 0, style: .precise)
        )
        WidgetFact(
            title: loc("Peak write"),
            value: Format.rate(history?.write.map(\.value).max() ?? 0, style: .precise)
        )
    }
}

/// When the last backup finished, from what macOS tells without Full Disk Access.
struct TimeMachineWidget: View {
    let context: TimeContext

    private static let settings = URL(string: "x-apple.systempreferences:com.apple.Time-Machine-Settings.extension")
    private static let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")

    private var header: some View {
        WidgetHeader(title: loc("Time Machine"), symbol: "clock.arrow.circlepath", tint: Palette.green)
    }

    var body: some View {
        switch context.snapshot.timeMachine?.state {
        case nil:
            WidgetEmptyState(symbol: "clock.arrow.circlepath", title: loc("Checking…"), tint: Palette.green)
        case .notConfigured:
            message(
                symbol: "exclamationmark.triangle.fill",
                title: loc("No backup disk"),
                detail: loc("Choose one in System Settings."),
                button: loc("Set Up…"),
                url: Self.settings
            )
        case .needsPermission:
            message(
                symbol: "lock.fill",
                title: loc("Full Disk Access needed"),
                detail: loc("macOS keeps backup history private."),
                button: loc("Open Privacy & Security…"),
                url: Self.privacy
            )
        case let .running(progress, secondsLeft):
            running(progress, secondsLeft)
        case .idle:
            if let status = context.snapshot.timeMachine, let last = status.lastBackup {
                idle(status, last: last)
            } else {
                message(
                    symbol: "exclamationmark.triangle.fill",
                    title: loc("Never backed up"),
                    detail: loc("Back up from System Settings."),
                    button: loc("Open Settings…"),
                    url: Self.settings
                )
            }
        }
    }

    private func message(symbol: String, title: String, detail: String, button: String, url: URL?) -> some View {
        VStack(spacing: 6) {
            WidgetEmptyState(
                symbol: symbol,
                title: title,
                detail: context.size == .small ? nil : detail,
                tint: Palette.orange
            )
            if context.size != .small, let url {
                Link(destination: url) {
                    Text(button)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .widgetSolid(Palette.blue, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func running(_ progress: Double?, _ secondsLeft: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(loc("Backing up…")).font(.system(size: 13, weight: .semibold))
            if let progress {
                Text(Format.percent(progress)).font(.widgetFigure(30)).foregroundStyle(Palette.blue).widgetAccentable()
                ThinBar(value: progress, tint: Palette.blue, height: 6)
            } else {
                Text(loc("Preparing…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let secondsLeft {
                Text(loc("\(CompactDuration.format(secondsLeft)) left"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func idle(_ status: TimeMachineStatus, last: Date) -> some View {
        switch context.size {
        case .small:
            VStack(alignment: .leading, spacing: 3) {
                header
                backedUp(status, last, size: 28)
                Spacer(minLength: 0)
                dots(status, days: 7)
            }
        case .medium:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    header
                    backedUp(status, last, size: 30)
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    disk(status)
                    Spacer(minLength: 0)
                    WidgetSection(title: loc("Last 14 days"))
                    dots(status, days: 14)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 9) {
                title(status)
                backedUp(status, last, size: 34)
                Divider()
                disk(status)
                recent(status, limit: 4)
                Spacer(minLength: 0)
            }
        case .extraLarge:
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    title(status)
                    backedUp(status, last, size: 44)
                    Divider()
                    disk(status)
                    Spacer(minLength: 0)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    WidgetSection(title: loc("Last 30 days"))
                    dots(status, days: 30)
                    recent(status, limit: 5)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func title(_ status: TimeMachineStatus) -> some View {
        WidgetTitle(
            title: loc("Time Machine"),
            symbol: "clock.arrow.circlepath",
            tint: Palette.green,
            note: status.isAutomatic ? loc("Automatic") : loc("Manual")
        )
    }

    private func backedUp(_ status: TimeMachineStatus, _ date: Date, size: CGFloat) -> some View {
        let isOverdue = status.isOverdue(at: context.now)
        let title = isOverdue ? loc("Backup overdue") : status.isConfirmed ? loc("Backed up") : loc("Last activity")
        return VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: isOverdue ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOverdue ? Palette.orange : Palette.green)
                .lineLimit(1)
                .widgetAccentable()
            Text(WidgetDuration.clock(date)).font(.widgetFigure(size)).monospacedDigit().lineLimit(1)
            Text(dayText(date)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func dayText(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: context.now)
            ? loc("Today")
            : date.formatted(.dateTime.day().month().year())
    }

    @ViewBuilder
    private func disk(_ status: TimeMachineStatus) -> some View {
        if let name = status.destination {
            VStack(alignment: .leading, spacing: 2) {
                WidgetSection(title: loc("Backup disk"))
                Label(name, systemImage: "externaldrive")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
        }
    }

    private func dots(_ status: TimeMachineStatus, days: Int) -> some View {
        HStack(spacing: days > 14 ? 2 : 4) {
            ForEach(status.days(days, at: context.now), id: \.date) { day in
                Circle()
                    .fill(day.backedUp ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.quaternary))
                    .frame(width: days > 14 ? 7 : 8, height: days > 14 ? 7 : 8)
                    .widgetAccentable(day.backedUp)
                    .help(day.date.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    private func recent(_ status: TimeMachineStatus, limit: Int) -> some View {
        if !status.backups.isEmpty {
            WidgetSection(title: loc("Recent backups"))
            ForEach(status.backups.reversed().prefix(limit), id: \.self) { date in
                Label(
                    date.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.system(size: 12))
            }
        }
    }
}
