import GlassWorkCore
import SwiftUI

struct VPNPanel: View {
    let reading: VPNReading?
    let since: Date?
    var now = Date()
    @Environment(\.panelActions) private var actions

    private static let settings = URL(
        string: "x-apple.systempreferences:com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension"
    )

    var body: some View {
        PanelFrame(
            module: .vpn,
            subtitle: subtitle,
            footerTitle: loc("Open VPN Settings…"),
            footerAction: { Self.settings.map(actions.openURL) }
        ) {
            if let reading, reading.isConfigured {
                status(reading)
                if reading.isConnected {
                    Divider()
                    details(reading)
                }
                if !reading.otherServices.isEmpty {
                    Divider()
                    ForEach(reading.otherServices) { service in
                        serviceRow(service)
                    }
                }
                ReadOnlyNote(text: loc("GlassWork only shows status; it never connects or disconnects."))
            } else if reading == nil {
                PanelMessage(symbol: "shield", title: loc("Checking…"))
            } else {
                PanelMessage(
                    symbol: "shield",
                    title: loc("No VPN"),
                    detail: loc("No VPN is set up on this Mac.")
                )
            }
        }
    }

    private var subtitle: String {
        guard let reading, !reading.services.isEmpty else { return "" }
        let connected = reading.services.count { $0.status == .connected }
        return loc("\(connected) of \(reading.services.count) connected")
    }

    private func status(_ reading: VPNReading) -> some View {
        HStack(spacing: 12) {
            Image(systemName: reading.isConnected ? "shield.fill" : "shield")
                .font(.system(size: 30))
                .foregroundStyle(reading.isConnected ? Palette.green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title(reading)).font(.system(size: 17, weight: .semibold))
                if let name = reading.connectedService?.name {
                    Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func title(_ reading: VPNReading) -> String {
        if reading.isConnected {
            return loc("Connected")
        }
        return reading.isConnecting ? loc("Connecting…") : loc("Not connected")
    }

    @ViewBuilder
    private func details(_ reading: VPNReading) -> some View {
        if let since {
            let time = since.formatted(date: .omitted, time: .shortened)
            InfoRow(title: loc("Since"), value: "\(time) · \(CompactDuration.format(now.timeIntervalSince(since)))")
        }
        if let tunnel = reading.tunnels.first {
            InfoRow(title: loc("Interface"), value: tunnel.name)
        }
        if let kind = reading.connectedService?.kind {
            InfoRow(title: loc("Type"), value: kind)
        }
        if let tunnel = reading.tunnels.first {
            InfoRow(title: loc("Tunnel address"), value: tunnel.address)
        }
    }

    private func serviceRow(_ service: VPNService) -> some View {
        HStack {
            Image(systemName: "shield").foregroundStyle(.secondary)
            Text("\(service.name) (\(service.kind))")
            Spacer()
            Text(service.status == .connecting ? loc("Connecting…") : loc("Not connected"))
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 12))
    }
}

struct WiFiPanel: View {
    let reading: WiFiReading?
    let signal: [History<Double>.Point]
    @Environment(\.panelActions) private var actions

    private static let settings = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")

    var body: some View {
        PanelFrame(
            module: .wifi,
            subtitle: subtitle,
            footerTitle: loc("Wi-Fi Settings…"),
            footerAction: { Self.settings.map(actions.openURL) }
        ) {
            switch reading {
            case let .connected(link): connected(link)
            case .notConnected: PanelMessage(symbol: "wifi", title: loc("Not connected"))
            case .off: PanelMessage(symbol: "wifi.slash", title: loc("Wi-Fi is off"))
            case .noHardware: PanelMessage(symbol: "wifi.slash", title: loc("No Wi-Fi on this Mac"))
            case nil: PanelMessage(symbol: "wifi", title: loc("Checking…"))
            }
        }
    }

    private var subtitle: String {
        reading?.link == nil ? "" : loc("Connected")
    }

    @ViewBuilder
    private func connected(_ link: WiFiLink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                BigFigure(text: DeveloperText.decibels(link.rssi))
                Spacer()
                quality(link.quality)
            }
            Text(loc("Signal (RSSI)")).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        VStack(spacing: 3) {
            InteractiveChart(
                series: [ChartSeries(
                    id: "signal",
                    title: loc("Signal"),
                    color: Palette.blue,
                    points: signal,
                    format: { DeveloperText.decibels(WiFiSignal.rssi(plotted: $0)) }
                )],
                domain: WiFiSignal.domain
            )
            HStack {
                Text(loc("60 s ago"))
                Spacer()
                Text(loc("now"))
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        Divider()
        InfoRow(title: loc("Band · channel"), value: channel(link))
        if let standard = link.standard {
            InfoRow(title: loc("PHY mode"), value: standard)
        }
        InfoRow(title: loc("Tx rate"), value: loc("\(Int(link.transmitRate.rounded())) Mb/s"))
        InfoRow(
            title: loc("Noise · SNR"),
            value: "\(DeveloperText.decibels(link.noise)) · \(loc("\(link.signalToNoise) dB"))"
        )
        ReadOnlyNote(text: loc("The network name is never read, so no Location permission is needed."))
    }

    private func channel(_ link: WiFiLink) -> String {
        let width = link.width.map { " (\(loc("\($0) MHz")))" } ?? ""
        return "\(link.band.title) · \(link.channel)\(width)"
    }

    private func quality(_ quality: WiFiQuality) -> some View {
        let label: (String, Color) = switch quality {
        case .excellent: (loc("Excellent"), Palette.green)
        case .good: (loc("Good"), Palette.green)
        case .fair: (loc("Fair"), Palette.orange)
        case .weak: (loc("Weak"), Palette.red)
        }
        return Text(label.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(label.1)
    }
}
