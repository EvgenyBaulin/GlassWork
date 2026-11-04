import GlassWorkCore
import SwiftUI
import WidgetKit

/// Batteries of connected accessories, lowest first.
struct DevicesWidget: View {
    let context: TimeContext

    private static let bluetooth = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")

    private var devices: [DeviceBattery] {
        context.snapshot.devices ?? []
    }

    var body: some View {
        if context.snapshot.devices == nil {
            WidgetChecking(symbol: "wave.3.right", tint: Palette.green)
        } else if devices.isEmpty {
            WidgetEmptyState(
                symbol: "wave.3.right",
                title: loc("No devices with a battery"),
                detail: context.size == .small ? nil : loc("Connect a mouse, keyboard or headphones."),
                tint: Palette.green
            )
        } else {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(devices.prefix(2)) { device in
                        HStack(spacing: 8) {
                            ring(device, diameter: 52)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(Format.percent(device.charge)).font(.widgetFigure(20)).monospacedDigit()
                                Text(device.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            case .medium:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: loc("Devices"), symbol: "wave.3.right", tint: Palette.green)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(devices.prefix(4)) { device in
                            VStack(spacing: 2) {
                                ring(device, diameter: 56)
                                Text(Format.percent(device.charge)).font(.system(
                                    size: 14,
                                    weight: .bold,
                                    design: .rounded
                                ))
                                Text(device.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 15) {
                    title
                    ForEach(devices.prefix(6)) { row($0) }
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                VStack(alignment: .leading, spacing: 10) {
                    title
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(devices.prefix(5)) { card($0) }
                        settingsCard
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var title: some View {
        WidgetTitle(
            title: loc("Devices"),
            symbol: "wave.3.right",
            tint: Palette.green,
            note: loc("\(devices.count) devices · lowest first")
        )
    }

    private func tint(_ device: DeviceBattery) -> Color {
        if device.charge < 0.2 {
            return Palette.red
        }
        return device.charge < 0.3 ? Palette.orange : Palette.green
    }

    private func symbol(_ device: DeviceBattery) -> String {
        switch device.kind {
        case .headphones: "airpods"
        case .mouse: "magicmouse"
        case .keyboard: "keyboard"
        case .trackpad: "rectangle.and.hand.point.up.left"
        case .other: "battery.75percent"
        }
    }

    private func ring(_ device: DeviceBattery, diameter: CGFloat) -> some View {
        RingGauge(value: device.charge, tint: tint(device), lineWidth: diameter / 11) {
            Image(systemName: symbol(device)).font(.system(size: diameter / 3)).foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .help(Format.percent(device.charge))
    }

    private func row(_ device: DeviceBattery) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(device))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(.quaternary.opacity(0.5), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer()
                    Text(Format.percent(device.charge)).font(.system(size: 13, weight: .bold)).monospacedDigit()
                }
                ThinBar(value: device.charge, tint: tint(device))
            }
        }
    }

    private func card(_ device: DeviceBattery) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ring(device, diameter: 62)
                Text(Format.percent(device.charge)).font(.widgetFigure(20)).monospacedDigit()
            }
            Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var settingsCard: some View {
        if let url = Self.bluetooth {
            Link(destination: url) {
                VStack(spacing: 5) {
                    Image(systemName: "wave.3.right").font(.system(size: 16)).foregroundStyle(.secondary)
                    Text(loc("Bluetooth Settings…")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Signal strength. The name of the network is never read, so no Location access is needed.
struct WiFiSignalWidget: View {
    let context: TimeContext
    var chartHover: Date?

    private var link: WiFiLink? {
        context.snapshot.wifi?.link
    }

    var body: some View {
        if let link {
            switch context.size {
            case .small:
                VStack(alignment: .leading, spacing: 3) {
                    header(link)
                    figure(link, size: 30)
                    Text(quality(link.quality).title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(quality(link.quality).tint)
                    Spacer(minLength: 0)
                    chart(seconds: 300, height: 30)
                }
            case .medium:
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        header(link)
                        figure(link, size: 32)
                        Text(loc("\(quality(link.quality).title) signal"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(quality(link.quality).tint)
                        Spacer(minLength: 0)
                        Text(channel(link)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        Text(loc("\(Int(link.transmitRate.rounded())) Mb/s"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        WidgetSection(title: loc("Last 5 min"))
                        chart(seconds: 300, height: 76)
                        Text(loc("Noise \(link.noise) dBm · SNR \(link.signalToNoise) dB"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            case .large:
                VStack(alignment: .leading, spacing: 8) {
                    WidgetTitle(
                        title: loc("Wi-Fi Signal"),
                        symbol: "wifi",
                        tint: Palette.blue,
                        note: loc("Name hidden")
                    )
                    summary(link, figure: 30)
                    WidgetSection(title: loc("Last 5 minutes"))
                    chart(seconds: 300, height: 76)
                    Divider()
                    facts(link)
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        WidgetTitle(title: loc("Wi-Fi Signal"), symbol: "wifi", tint: Palette.blue)
                        summary(link, figure: 40)
                        qualityScale(link)
                        Spacer(minLength: 0)
                        Text(loc("The network name is never read, so no Location permission is needed."))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        WidgetSection(title: loc("Last 10 minutes"))
                        chart(seconds: 600, height: 110)
                        facts(link)
                        if let standard = link.standard {
                            WidgetFact(title: loc("Standard"), value: standard)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        } else if context.snapshot.wifi == nil {
            WidgetChecking(symbol: "wifi", tint: Palette.blue)
        } else {
            WidgetEmptyState(symbol: "wifi.slash", title: emptyTitle, tint: Palette.blue)
        }
    }

    private var emptyTitle: String {
        switch context.snapshot.wifi {
        case .noHardware: loc("No Wi-Fi on this Mac")
        case .off: loc("Wi-Fi is off")
        default: loc("Not connected")
        }
    }

    private func header(_ link: WiFiLink) -> some View {
        HStack {
            WidgetHeader(title: loc("Wi-Fi"), symbol: "wifi", tint: Palette.teal)
            Spacer()
            Image(systemName: "wifi", variableValue: Double(link.bars) / 3)
                .font(.system(size: 14))
                .foregroundStyle(quality(link.quality).tint)
                .widgetAccentable()
        }
    }

    private func figure(_ link: WiFiLink, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: "−\(abs(link.rssi))").font(.widgetFigure(size)).monospacedDigit()
            Text(verbatim: "dBm").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func summary(_ link: WiFiLink, figure size: CGFloat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi", variableValue: Double(link.bars) / 3)
                .font(.system(size: size))
                .foregroundStyle(quality(link.quality).tint)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                figure(link, size: size)
                Text(loc("\(quality(link.quality).title) signal"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(quality(link.quality).tint)
            }
        }
    }

    private func quality(_ quality: WiFiQuality) -> (title: String, tint: Color) {
        switch quality {
        case .excellent: (loc("Excellent"), Palette.teal)
        case .good: (loc("Good"), Palette.green)
        case .fair: (loc("Fair"), Palette.orange)
        case .weak: (loc("Weak"), Palette.red)
        }
    }

    private func channel(_ link: WiFiLink) -> String {
        loc("Ch \(link.channel) · \(link.band.title)")
    }

    private func chart(seconds: TimeInterval, height: CGFloat) -> some View {
        let since = context.now.addingTimeInterval(-seconds)
        return InteractiveChart(
            series: [ChartSeries(
                id: "signal",
                title: loc("Signal"),
                color: Palette.teal,
                points: (context.snapshot.wifiHistory ?? []).filter { $0.date >= since },
                format: { DeveloperText.decibels(WiFiSignal.rssi(plotted: $0)) }
            )],
            domain: WiFiSignal.domain,
            height: height,
            initialHover: chartHover
        )
    }

    @ViewBuilder
    private func facts(_ link: WiFiLink) -> some View {
        WidgetFact(title: loc("Noise"), value: DeveloperText.decibels(link.noise))
        WidgetFact(title: loc("SNR"), value: loc("\(link.signalToNoise) dB"))
        WidgetFact(title: loc("Channel"), value: channelDetail(link))
        WidgetFact(title: loc("Tx rate"), value: loc("\(Int(link.transmitRate.rounded())) Mb/s"))
    }

    private func channelDetail(_ link: WiFiLink) -> String {
        let width = link.width.map { " · \(loc("\($0) MHz"))" } ?? ""
        return "\(link.channel) · \(link.band.title)\(width)"
    }

    /// Four bands from weak to excellent with a marker where the signal is now.
    private func qualityScale(_ link: WiFiLink) -> some View {
        let bands: [WiFiQuality] = [.weak, .fair, .good, .excellent]
        let share = min(max((Double(link.rssi) + 90) / 50, 0), 1)
        return VStack(alignment: .leading, spacing: 3) {
            WidgetSection(title: loc("Signal quality"))
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 2) {
                        ForEach(bands, id: \.self) { band in
                            Capsule().fill(quality(band).tint).frame(height: 5)
                        }
                    }
                    .offset(y: 8)
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 7))
                        .offset(x: geometry.size.width * share - 3.5)
                }
            }
            .frame(height: 14)
            HStack(spacing: 2) {
                ForEach(bands, id: \.self) { band in
                    Text(quality(band).title)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
