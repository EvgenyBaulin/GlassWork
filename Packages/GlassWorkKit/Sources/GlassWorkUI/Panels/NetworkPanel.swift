import GlassWorkCore
import SwiftUI

struct NetworkPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        NetworkPanelContent(
            network: monitor.network,
            points: { monitor.points($0, in: $1) },
            localIP: NetworkReader.localAddress()
        )
    }
}

/// The Network panel for one sample. Without a route it shows an offline banner instead of zero rates.
struct NetworkPanelContent: View {
    let network: NetworkSample?
    let points: (Metric, TieredHistory.Range) -> [History<Double>.Point]
    let localIP: String?
    @State private var range = TieredHistory.Range.minute
    @State private var showsPublicIP = false
    @State private var publicIP: String?

    var body: some View {
        PanelFrame(module: .network, subtitle: network?.interfaces.first?.name ?? "") {
            if network?.isOffline == true {
                PanelBanner(
                    symbol: "wifi.slash",
                    title: loc("No network connection"),
                    message: loc("Check Wi-Fi or Ethernet. Rates return when a connection is back.")
                )
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    BigFigure(text: network.map { "↓ \(Format.rate($0.download, style: .precise))" } ?? "—")
                    Text(network.map { "↑ \(Format.rate($0.upload, style: .precise))" } ?? "—")
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
            }
            Divider()
            if let network {
                if !network.isOffline {
                    PanelSection(title: loc("Interfaces"), caption: "↓ · ↑") {
                        ForEach(network.interfaces, id: \.name) { interface in
                            InfoRow(
                                title: interface.name,
                                value: "↓ \(Format.rate(interface.download, style: .precise))  ↑ \(Format.rate(interface.upload, style: .precise))"
                            )
                        }
                    }
                    Divider()
                }
                InfoRow(
                    title: loc("This session"),
                    value: "↓ \(Format.bytes(Double(network.sessionReceived), style: .precise))  ↑ \(Format.bytes(Double(network.sessionSent), style: .precise))"
                )
            }
            InfoRow(title: loc("Local IP"), value: localIP ?? "—")
            Toggle(isOn: $showsPublicIP) {
                HStack {
                    Text(loc("Public IP")).foregroundStyle(.secondary)
                    Spacer()
                    Text(showsPublicIP ? publicIP ?? "…" : "•••.•••.•••.•••").monospacedDigit()
                }
                .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(loc("Contacts an external service"))
            .task(id: showsPublicIP) {
                publicIP = showsPublicIP ? await NetworkReader.publicAddress() : nil
            }
        }
    }

    private func series(_ id: String, _ title: String, _ color: Color, _ metric: Metric) -> ChartSeries {
        ChartSeries(id: id, title: title, color: color, points: points(metric, range)) {
            Format.rate($0, style: .precise)
        }
    }
}
