import GlassWorkCore
import SwiftUI

public extension SensorGroup {
    var title: String {
        switch self {
        case .cpuPerformance: loc("CPU · Performance")
        case .cpuEfficiency: loc("CPU · Efficiency")
        case .gpu: loc("GPU")
        case .soc: loc("SoC and memory")
        case .battery: loc("Battery")
        case .storage: loc("SSD")
        case .power: loc("Power")
        case .ambient: loc("Ambient")
        case .other: loc("Other")
        }
    }
}

/// Every sensor this Mac exposes, grouped, with session minimum and maximum.
struct SensorsPanel: View {
    let monitor: SystemMonitor
    @State private var query = ""
    @State private var extremes: [String: ClosedRange<Double>] = [:]
    @Environment(\.panelActions) private var actions

    private var groups: [SensorGroup] {
        let showsUnknown = actions.moduleOptions(.sensors).flag(ItemOption.showsUnknownSensors, default: true)
        return SensorGroup.allCases.filter { showsUnknown || $0 != .other }
    }

    var body: some View {
        let sample = monitor.sensors
        PanelFrame(module: .sensors, subtitle: loc("\(sample?.readings.count ?? 0) sensors")) {
            if let sample, !sample.readings.isEmpty {
                averages(sample)
                TextField(loc("Search sensors"), text: $query).textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.self) { group in
                            section(group, readings: filtered(sample, group))
                        }
                    }
                }
                .frame(maxHeight: 340)
                Button(loc("Copy all")) { copy(sample) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.system(size: 12))
            } else {
                Text(loc("No sensors available on this Mac"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .onChange(of: monitor.sensors) { _, new in track(new) }
    }

    private func averages(_ sample: SensorSample) -> some View {
        HStack(spacing: 8) {
            average(loc("avg CPU"), sample.averageCPU, Palette.blue)
            average(loc("avg GPU"), sample.averageGPU, Palette.purple)
            average(loc("avg SoC"), sample.averageSoC, Palette.teal)
        }
    }

    private func average(_ title: String, _ value: Double?, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(tint)
            Text(value.map(Format.temperature) ?? "—")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filtered(_ sample: SensorSample, _ group: SensorGroup) -> [SensorReading] {
        sample.readings.filter { reading in
            reading.group == group && (query.isEmpty
                || reading.key.localizedCaseInsensitiveContains(query)
                || group.title.localizedCaseInsensitiveContains(query))
        }
    }

    @ViewBuilder
    private func section(_ group: SensorGroup, readings: [SensorReading]) -> some View {
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.system(size: 12, weight: .semibold))
                ForEach(readings) { row($0) }
            }
        }
    }

    private func row(_ reading: SensorReading) -> some View {
        let range = extremes[reading.key]
        return HStack {
            Text(reading.key).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            if let range {
                Text("\(Format.temperature(range.lowerBound)) – \(Format.temperature(range.upperBound))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Text(Format.temperature(reading.celsius))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func track(_ sample: SensorSample?) {
        for reading in sample?.readings ?? [] {
            let old = extremes[reading.key] ?? reading.celsius ... reading.celsius
            extremes[reading.key] = min(old.lowerBound, reading.celsius) ... max(old.upperBound, reading.celsius)
        }
    }

    private func copy(_ sample: SensorSample) {
        let text = sample.readings.map { "\($0.key)\t\(String(format: "%.1f", $0.celsius))" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
