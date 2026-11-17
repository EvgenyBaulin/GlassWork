import GlassWorkCore
import SwiftUI

struct CommandsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Commands"), symbol: "terminal", tint: Palette.blue)
            if snapshot.commands.isEmpty {
                Text(loc("Add commands in Settings")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(snapshot.commands.prefix(size == .small ? 2 : 6)) { command in
                row(command, result: snapshot.commandResults[command.id])
            }
        }
    }

    private func row(_ command: UserCommand, result: CommandResult?) -> some View {
        HStack(spacing: 8) {
            // Commands that ask first run from Settings, where the question can be shown.
            if !command.asksFirst {
                WidgetActionButton(action: .runCommand(command.id)) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Palette.blue)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(command.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let result {
                    Text(loc("Exit \(Int(result.status)) · \(CompactDuration.format(result.duration))"))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(result.status == 0 ? Palette.green : Palette.red)
                }
            }
        }
    }
}

struct EndpointsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        let down = snapshot.endpoints.filter { endpoint in
            snapshot.endpointChecks[endpoint.id]?.last?.isUp(expected: endpoint.expectedStatus) == false
        }
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Endpoints"), symbol: "dot.radiowaves.left.and.right", tint: Palette.teal)
            Text("\(snapshot.endpoints.count - down.count)/\(snapshot.endpoints.count)")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            if !down.isEmpty {
                Text(loc("\(down.count) down")).font(.system(size: 13)).foregroundStyle(Palette.red)
            }
            ForEach(snapshot.endpoints.prefix(size == .small ? 0 : 4)) { endpoint in
                Text(endpoint.url.host() ?? endpoint.url.absoluteString)
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
        }
    }
}

/// Weeks as columns; hovering a cell shows its date and count in the shared tooltip.
struct HeatMap: View {
    let days: [ContributionDay]
    var initialHover: CGPoint?

    /// Side of a cell and the gap between cells; a cell is 8 pt, the smallest hover target.
    static let cell: CGFloat = 8
    static let gap: CGFloat = 2
    static let rows = 7

    /// The day under a point of the grid. Cells fill the columns top to bottom, and the gaps belong to the
    /// nearest cell so the pointer never falls between two of them.
    static func index(at point: CGPoint, count: Int) -> Int? {
        let pitch = cell + gap
        guard point.x >= 0, point.y >= 0 else { return nil }
        let row = Int(point.y / pitch)
        let column = Int(point.x / pitch)
        guard row < rows else { return nil }
        let index = column * rows + row
        return index < count ? index : nil
    }

    var body: some View {
        let peak = max(days.map(\.contributions).max() ?? 1, 1)
        LazyHGrid(
            rows: Array(repeating: GridItem(.fixed(Self.cell), spacing: Self.gap), count: Self.rows),
            spacing: Self.gap
        ) {
            ForEach(days, id: \.date) { day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.green
                        .opacity(day
                            .contributions == 0 ? 0.12 : 0.3 + 0.7 * Double(day.contributions) / Double(peak)))
                    .frame(width: Self.cell, height: Self.cell)
            }
        }
        .hoverReadout(initialHover: initialHover) { point, _ in
            Self.index(at: point, count: days.count).map {
                [HoverRow(
                    title: days[$0].date,
                    value: loc("\(days[$0].contributions) contributions"),
                    color: Palette.green
                ).tooltipRow]
            }
        }
    }
}
