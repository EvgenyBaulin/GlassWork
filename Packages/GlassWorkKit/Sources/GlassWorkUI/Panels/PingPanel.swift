import GlassWorkCore
import SwiftUI

struct PingPanel: View {
    let log: PingLog
    let host: String
    @State private var isChangingHost = false
    @Environment(\.panelActions) private var actions

    var body: some View {
        PanelFrame(
            module: .ping,
            subtitle: loc("every 30 s"),
            footerTitle: loc("Change Host…"),
            footerAction: { isChangingHost.toggle() }
        ) {
            VStack(alignment: .leading, spacing: 2) {
                headline
                Text(host).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            if isChangingHost {
                PingHostField(host: host) { value in
                    actions.setOption(.ping, DeveloperOptions.Key.host, value)
                    isChangingHost = false
                }
            }
            chart
            if let stats = log.stats {
                Divider()
                statsRow(stats)
            }
            if let since = log.upSince {
                Divider()
                InfoRow(title: loc("Up since"), value: since.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    @ViewBuilder
    private var headline: some View {
        if log.isDown {
            BigFigure(text: loc("No reply")).foregroundStyle(Palette.red)
        } else if log.isOffline {
            BigFigure(text: loc("Offline")).foregroundStyle(.secondary)
        } else {
            BigFigure(text: log.latest?.milliseconds.map(DeveloperText.milliseconds) ?? "—")
        }
    }

    private var chart: some View {
        VStack(spacing: 3) {
            InteractiveChart(series: [
                ChartSeries(
                    id: "latency",
                    title: loc("Latency"),
                    color: Palette.teal,
                    points: log.latency,
                    format: DeveloperText.milliseconds
                ),
                ChartSeries(
                    id: "loss",
                    title: loc("Loss"),
                    color: Palette.red,
                    points: log.rollingLoss,
                    isPlotted: false,
                    format: { Format.percent($0) }
                ),
            ])
            HStack {
                Text(loc("30 min ago"))
                Spacer()
                Text(loc("now"))
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
    }

    private func statsRow(_ stats: PingStats) -> some View {
        HStack {
            stat(loc("Min"), DeveloperText.milliseconds(stats.minimum))
            stat(loc("Avg"), DeveloperText.milliseconds(stats.average))
            stat(loc("Max"), DeveloperText.milliseconds(stats.maximum))
            stat(loc("Jitter"), DeveloperText.milliseconds(stats.jitter))
            stat(loc("Loss"), Format.percent(stats.loss))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Host name or IPv4 address; anything else is refused before it reaches settings.
struct PingHostField: View {
    @State private var text: String
    private let onCommit: (String) -> Void

    init(host: String, onCommit: @escaping (String) -> Void) {
        _text = State(initialValue: host)
        self.onCommit = onCommit
    }

    private var isValid: Bool {
        PingHost.isValid(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            TextField(loc("Host or IP address"), text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if isValid {
                        onCommit(text)
                    }
                }
            if !isValid {
                Text(loc("Enter a host name or an IPv4 address."))
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.red)
            }
        }
    }
}
