import GlassWorkCore
import SwiftUI

/// Every sensor of a sample in groups, flowed into columns of a given height. What does not fit is counted, not drawn.
struct SensorListLayout: Equatable {
    enum Entry: Identifiable, Equatable {
        case header(SensorGroup, average: Double)
        case row(SensorReading)

        var id: String {
            switch self {
            case let .header(group, _): "group-\(group.rawValue)"
            case let .row(reading): reading.key
            }
        }
    }

    static let rowHeight: CGFloat = 17
    static let headerHeight: CGFloat = 22

    var columns: [[Entry]]
    var hidden: Int

    init(sample: SensorSample, columns count: Int, height: CGFloat) {
        var columns: [[Entry]] = [[]]
        var used: CGFloat = 0
        var hidden = 0
        for group in SensorGroup.allCases {
            let readings = sample.readings.filter { $0.group == group }
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            guard !readings.isEmpty else { continue }
            let average = readings.map(\.celsius).reduce(0, +) / Double(readings.count)
            var pending = readings[...]
            while !pending.isEmpty {
                if used + Self.headerHeight + Self.rowHeight > height {
                    guard columns.count < count else { break }
                    columns.append([])
                    used = 0
                    // A column that is too short for even one row would otherwise loop here.
                    guard Self.headerHeight + Self.rowHeight <= height else { break }
                }
                columns[columns.count - 1].append(.header(group, average: average))
                used += Self.headerHeight
                while let reading = pending.first, used + Self.rowHeight <= height {
                    columns[columns.count - 1].append(.row(reading))
                    used += Self.rowHeight
                    pending = pending.dropFirst()
                }
            }
            hidden += pending.count
        }
        self.columns = columns
        self.hidden = hidden
    }
}

/// The sensors of the Temperature and Fans widgets, grouped, one reading per line.
struct WidgetSensorList: View {
    let sample: SensorSample
    let columns: Int
    let height: CGFloat

    var body: some View {
        let layout = SensorListLayout(sample: sample, columns: columns, height: height)
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(column) { entry in
                            view(entry)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            if layout.hidden > 0 {
                Text(loc("+\(layout.hidden) more sensors in the app"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func view(_ entry: SensorListLayout.Entry) -> some View {
        switch entry {
        case let .header(group, average):
            HStack {
                Text(group.title.uppercased()).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(Format.temperature(average)).monospacedDigit()
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(height: SensorListLayout.headerHeight, alignment: .bottom)
        case let .row(reading):
            HStack {
                Text(reading.key).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(Format.temperature(reading.celsius))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(reading.celsius >= 90 ? Palette.red : .primary)
            }
            .lineLimit(1)
            .frame(height: SensorListLayout.rowHeight)
        }
    }
}
