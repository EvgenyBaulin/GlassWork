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

/// Every sensor this Mac exposes, grouped, with a short history and the session minimum and maximum.
struct SensorsPanel: View {
    let monitor: SystemMonitor
    @Environment(\.panelActions) private var actions

    var body: some View {
        SensorsPanelContent(
            sample: monitor.sensors,
            tracker: monitor.sensorTracks,
            groups: SensorGroupOptions(options: actions.moduleOptions(.sensors)).shownGroups
        )
    }
}

struct SensorsPanelContent: View {
    let sample: SensorSample?
    let tracker: SensorTracker
    let groups: [SensorGroup]
    /// Starts a sparkline as if the cursor were on its newest point, for tests of the hover state.
    var hoveredKey: String?
    @State private var query = ""

    var body: some View {
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
        SensorRow(
            reading: reading,
            track: tracker.track(for: reading.key),
            hovered: hoveredKey == reading.key
        )
    }

    private func copy(_ sample: SensorSample) {
        let text = sample.readings.map { "\($0.key)\t\(String(format: "%.1f", $0.celsius))" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// One sensor: its name, session range, a sparkline of the latest readings and the current value.
private struct SensorRow: View {
    let reading: SensorReading
    let track: SensorTrack?
    let hovered: Bool
    /// The row under the cursor goes above the next ones, so the sparkline's readout is not covered.
    @State private var isOver = false

    var body: some View {
        HStack(spacing: 8) {
            Text(reading.key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let track {
                Text("\(Format.temperature(track.minimum)) – \(Format.temperature(track.maximum))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
                sparkline(track)
            }
            Text(Format.temperature(reading.celsius))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(width: 42, alignment: .trailing)
        }
        .onHover { isOver = $0 }
        .zIndex(isOver || hovered ? 1 : 0)
    }

    private func sparkline(_ track: SensorTrack) -> some View {
        let points = track.points
        let values = points.map(\.value)
        // A flat sensor would fill the whole height, so the scale is at least four degrees wide.
        let low = (values.min() ?? 0)
        let high = max(values.max() ?? 0, low + 4)
        return InteractiveChart(
            series: [ChartSeries(
                id: reading.key,
                title: reading.key,
                color: Palette.orange,
                points: points,
                format: Format.temperature
            )],
            domain: (low - 1) ... (high + 1),
            height: 22,
            tooltipDate: Date.FormatStyle(date: .omitted, time: .standard),
            initialHover: hovered ? points.last?.date : nil
        )
        .frame(width: 64)
    }
}
