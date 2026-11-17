import GlassWorkCore
import SwiftUI

/// Stands in for a GitHub widget when `gh` is missing or not signed in, so it never shows an empty or stale list.
/// With no answer yet (an older snapshot) the content is shown as before.
struct GitHubAccessGate<Content: View>: View {
    let access: WidgetGitHub.Access?
    let size: WidgetSize
    let symbol: String
    var tint: Color = Palette.purple
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch access {
        case .notInstalled:
            WidgetEmptyState(
                symbol: symbol,
                title: loc("The gh tool is not installed"),
                detail: size == .small ? nil : "brew install gh",
                tint: tint
            )
        case .notSignedIn:
            WidgetEmptyState(
                symbol: symbol,
                title: loc("Not signed in to gh"),
                detail: size == .small ? nil : "gh auth login",
                tint: tint
            )
        case .ready, .none:
            content()
        }
    }
}

struct ReviewsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    var now: Date = .now

    private static let symbol = "arrow.triangle.pull"

    var body: some View {
        GitHubAccessGate(access: snapshot.githubAccess, size: size, symbol: Self.symbol) {
            content
        }
    }

    private var content: some View {
        let wait = ReviewWait(reviews: snapshot.reviews, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("Reviews"), symbol: Self.symbol, tint: Palette.purple)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(snapshot.reviews.count)").font(.system(size: 30, weight: .semibold, design: .rounded))
                Text(loc("to review")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(snapshot.reviews.prefix(rows)) { pull in
                row(pull)
            }
            if size == .large || size == .extraLarge, let oldest = wait.oldest {
                Spacer(minLength: 0)
                Divider()
                Text(loc("Oldest wait: \(CompactDuration.format(oldest))"))
                    .font(.system(size: 12, weight: .medium))
                buckets(wait)
            }
        }
    }

    private var rows: Int {
        switch size {
        case .small: 1
        case .medium: 3
        case .large: 6
        case .extraLarge: 6
        }
    }

    private func row(_ pull: PullRequest) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pull.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text("\(pull.repository)#\(pull.number)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if size != .small, let created = pull.createdAt {
                Spacer(minLength: 4)
                Text(CompactDuration.format(max(now.timeIntervalSince(created), 0)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buckets(_ wait: ReviewWait) -> some View {
        HStack(spacing: 12) {
            bucket(loc("Under a day"), count: wait.fresh, tint: Palette.green)
            bucket(loc("1–3 days"), count: wait.middle, tint: Palette.orange)
            bucket(loc("Over 3 days"), count: wait.stale, tint: Palette.red)
        }
    }

    private func bucket(_ title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 7, height: 7).widgetAccentable()
            Text(verbatim: "\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

struct ActionsWidget: View {
    let size: WidgetSize
    let snapshot: WidgetSnapshot
    var now: Date = .now

    private static let symbol = "play.circle"

    var body: some View {
        GitHubAccessGate(access: snapshot.githubAccess, size: size, symbol: Self.symbol, tint: Palette.blue) {
            content
        }
    }

    private var content: some View {
        let summary = WorkflowSummary(runs: snapshot.runs, now: now)
        return VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: loc("GitHub Actions"), symbol: Self.symbol, tint: Palette.blue)
            if snapshot.runs.isEmpty {
                Text(loc("No recent runs")).font(.system(size: 13)).foregroundStyle(.secondary)
            } else {
                totals(summary)
            }
            ForEach(snapshot.runs.prefix(rows)) { run in
                row(run)
            }
            if size == .large || size == .extraLarge, let rate = summary.weekSuccessRate {
                Spacer(minLength: 0)
                Divider()
                successRate(rate, summary: summary)
            }
        }
    }

    private var rows: Int {
        switch size {
        case .small: 2
        case .medium: 3
        case .large: 7
        case .extraLarge: 7
        }
    }

    private func totals(_ summary: WorkflowSummary) -> some View {
        HStack(spacing: 10) {
            Text(loc("\(summary.running) running now"))
                .foregroundStyle(summary.running > 0 ? Palette.orange : .secondary)
            if size != .small {
                Text(loc("\(summary.today) today")).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
    }

    private func row(_ run: WorkflowRun) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol(run.state)).foregroundStyle(tint(run.state))
            VStack(alignment: .leading, spacing: 0) {
                Text(run.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(verbatim: [run.repositoryName, run.branch].compactMap(\.self).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if size != .small, let timing = timing(run) {
                Spacer(minLength: 4)
                Text(timing)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// How long a run has been going, or how long it took and when it ended.
    private func timing(_ run: WorkflowRun) -> String? {
        if run.state == .running {
            return CompactDuration.format(max(now.timeIntervalSince(run.startedAt ?? run.createdAt), 0))
        }
        guard let duration = run.duration else { return nil }
        guard let ended = run.completedAt else { return CompactDuration.format(duration) }
        let ago = CompactDuration.format(max(now.timeIntervalSince(ended), 0))
        return loc("\(CompactDuration.format(duration)) · \(ago) ago")
    }

    private func successRate(_ rate: Double, summary: WorkflowSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc("7-day success")).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                Text(verbatim: "\(Int((rate * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            ThinBar(
                value: rate,
                tint: rate >= 0.9 ? Palette.green : rate >= 0.7 ? Palette.orange : Palette.red,
                readout: [HoverRow(
                    title: loc("Passed"),
                    value: "\(Int((rate * Double(summary.weekFinished)).rounded())) / \(summary.weekFinished)",
                    color: Palette.green
                )]
            )
            if let average = summary.averageDuration {
                Text(loc("Average run \(CompactDuration.format(average))"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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
        GitHubAccessGate(
            access: snapshot.githubAccess,
            size: size,
            symbol: "square.grid.3x3.fill",
            tint: Palette.green
        ) {
            content
        }
    }

    private var content: some View {
        let days = snapshot.contributions
        let total = days.map(\.contributions).reduce(0, +)
        let weeks = size == .small ? 12 : size == .extraLarge ? 52 : 26
        return VStack(alignment: .leading, spacing: 8) {
            Text(loc("\(total) contributions"))
                .font(.system(size: 15, weight: .semibold))
            HeatMap(days: Array(days.suffix(weeks * 7)))
            Text(loc("Streak: \(GitHubParser.currentStreak(days)) days"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if size == .large || size == .extraLarge, let summary = snapshot.contributionSummary {
                Divider()
                breakdown(summary)
                Spacer(minLength: 0)
            }
        }
    }

    private func breakdown(_ summary: ContributionSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                figure(summary.commits, loc("Commits"))
                figure(summary.pullRequests, loc("Pull requests"))
                figure(summary.issues, loc("Issues"))
            }
            if !summary.repositories.isEmpty {
                WidgetSection(title: loc("Top repositories"))
                ForEach(summary.repositories, id: \.name) { repository in
                    HStack {
                        Text(repository.name).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(loc("\(repository.commits) commits"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private func figure(_ value: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "\(value)").font(.widgetFigure(22)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
