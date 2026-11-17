import GlassWorkCore
import SwiftUI

struct BatteryPanel: View {
    let monitor: SystemMonitor

    var body: some View {
        BatteryPanelContent(battery: monitor.battery, apps: monitor.apps.apps)
            .onAppear { monitor.apps.refresh() }
    }
}

/// The Battery panel for a reading and the apps running. Plugged in or not, the list shows who uses the most.
struct BatteryPanelContent: View {
    let battery: BatterySample?
    let apps: [AppUsage]
    @Environment(\.panelActions) private var actions

    /// Apps under this much of one core are not worth a line.
    static let significantCPU = 1.0
    static let listLength = 5

    /// The busiest apps, by CPU since the last read.
    static func energyApps(_ apps: [AppUsage]) -> [AppUsage] {
        Array(apps.sorted(by: .cpu).filter { $0.cpu >= significantCPU }.prefix(listLength))
    }

    var body: some View {
        PanelFrame(
            module: .battery,
            subtitle: battery?.isOnAC == true ? loc("Power Adapter") : loc("On battery"),
            footerTitle: loc("Battery Settings…"),
            footerAction: {
                actions.openURL(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
            }
        ) {
            if let battery {
                summary(battery)
                Divider()
                details(battery)
                energyApps
            } else {
                Text(loc("This Mac has no battery"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
    }

    private func summary(_ battery: BatterySample) -> some View {
        HStack(spacing: 14) {
            RingGauge(value: battery.charge, tint: battery.charge < 0.2 ? Palette.red : Palette.green, lineWidth: 8) {
                Text(Format.percent(battery.charge)).font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(timeText(battery)).font(.system(size: 16, weight: .semibold))
                Text(battery.isCharging ? loc("Charging") : loc("At current use"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var energyApps: some View {
        let top = Self.energyApps(apps)
        if !top.isEmpty {
            Divider()
            VStack(spacing: 6) {
                Text(loc("Using significant energy"))
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(top) { app in
                    InfoRow(title: app.name, value: Format.corePercent(app.cpu))
                }
                Text(loc("By recent CPU use, as a share of one core"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func timeText(_ battery: BatterySample) -> String {
        guard let minutes = battery.minutesRemaining else { return loc("Calculating…") }
        let time = "\(minutes / 60):" + String(format: "%02d", minutes % 60)
        return battery.isCharging ? loc("\(time) to full") : loc("\(time) left")
    }

    private func details(_ battery: BatterySample) -> some View {
        VStack(spacing: 6) {
            if let health = battery.health {
                InfoRow(title: loc("Health"), value: Format.percent(health))
            }
            if let cycles = battery.cycleCount {
                InfoRow(title: loc("Cycle count"), value: "\(cycles)")
            }
            InfoRow(title: loc("Power source"), value: battery.isOnAC ? loc("Power Adapter") : loc("Battery"))
            if let watts = battery.adapterWatts {
                InfoRow(title: loc("Adapter"), value: "\(watts) W")
            }
            if let celsius = battery
                .temperature
            {
                InfoRow(title: loc("Temperature"), value: Format.temperature(celsius))
            }
        }
    }
}
