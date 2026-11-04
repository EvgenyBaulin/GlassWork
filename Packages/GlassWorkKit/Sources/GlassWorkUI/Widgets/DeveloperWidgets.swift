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
            // Commands that ask first run from their panel, where the question can be shown.
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

struct ReviewsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Reviews"), symbol: "arrow.triangle.pull", tint: Palette.purple)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.reviews.count)").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(loc("to review")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(snapshot.reviews.prefix(size == .small ? 1 : 5)) { pull in
                VStack(alignment: .leading, spacing: 1) {
                    Text(pull.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text("\(pull.repository)#\(pull.number)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ActionsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("GitHub Actions"), symbol: "play.circle", tint: Palette.blue)
            ForEach(snapshot.runs.prefix(size == .small ? 2 : 6)) { run in
                HStack(spacing: 6) {
                    Image(systemName: symbol(run.state)).foregroundStyle(tint(run.state))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(run.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(run.branch).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    private func symbol(_ state: WorkflowState) -> String {
        switch state {
        case .running: "clock"
        case .passed: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .other: "minus.circle"
        }
    }

    private func tint(_ state: WorkflowState) -> Color {
        switch state {
        case .running: Palette.orange
        case .passed: Palette.green
        case .failed: Palette.red
        case .other: Palette.gray
        }
    }
}

struct ContributionsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot

    var body: some View {
        let days = snapshot.contributions
        let total = days.map(\.contributions).reduce(0, +)
        let weeks = size == .small ? 12 : size == .extraLarge ? 52 : 26
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("\(total) contributions"))
                .font(.system(size: 15, weight: .semibold))
            HeatMap(days: Array(days.suffix(weeks * 7)))
            Text(loc("Streak: \(GitHubParser.currentStreak(days)) days"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }
}

/// Weeks as columns; hovering a cell shows its date and count.
struct HeatMap: View {
    let days: [ContributionDay]
    @State private var hovered: ContributionDay?

    var body: some View {
        let peak = max(days.map(\.contributions).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(8), spacing: 2), count: 7), spacing: 2) {
                ForEach(days, id: \.date) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.green
                            .opacity(day
                                .contributions == 0 ? 0.12 : 0.3 + 0.7 * Double(day.contributions) / Double(peak)))
                        .frame(width: 8, height: 8)
                        .onHover { hovered = $0 ? day : (hovered == day ? nil : hovered) }
                }
            }
            if let hovered {
                Text("\(hovered.date) · \(hovered.contributions)").font(.system(size: 11)).monospacedDigit()
            }
        }
    }
}
