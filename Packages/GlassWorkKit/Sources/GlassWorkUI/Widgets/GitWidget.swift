import GlassWorkCore
import SwiftUI
import WidgetKit

/// Which projects have something to do. Only reads: no fetch, no commit.
struct GitWidget: View {
    let context: TimeContext

    private var reading: GitReading? {
        context.snapshot.git
    }

    private var projects: [GitRepository] {
        reading?.byWork ?? []
    }

    private var toDo: Int {
        projects.count(where: \.needsWork)
    }

    private var header: some View {
        WidgetHeader(title: loc("Git"), symbol: "arrow.triangle.branch", tint: Palette.orange)
    }

    var body: some View {
        if reading == nil {
            WidgetChecking(symbol: "arrow.triangle.branch", tint: Palette.orange)
        } else if case .notInstalled = reading {
            WidgetEmptyState(symbol: "arrow.triangle.branch", title: loc("Git is not installed"))
        } else if projects.isEmpty {
            WidgetEmptyState(
                symbol: "folder",
                title: loc("No repositories found"),
                detail: context.size == .small ? nil : loc("Projects in ~/Developer appear here."),
                tint: Palette.orange
            )
        } else {
            switch context.size {
            case .small: small
            case .medium: medium
            case .large:
                VStack(alignment: .leading, spacing: 6) {
                    header
                    count(size: 30)
                    pills
                    Divider()
                    ForEach(projects.prefix(6)) { row($0) }
                    Spacer(minLength: 0)
                }
            case .extraLarge:
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        header
                        pills
                        ForEach(projects.prefix(6)) { row($0) }
                        Spacer(minLength: 0)
                    }
                    Divider()
                    details(projects[0])
                }
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if toDo == 0 {
                Spacer(minLength: 0)
                Label(loc("All up to date"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.green)
                    .widgetAccentable()
                Spacer(minLength: 0)
            } else {
                count(size: 30)
                pills
                Spacer(minLength: 0)
                if let top = projects.first {
                    Text(top.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    HStack {
                        Text(top.status?.head ?? "—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        counts(top)
                    }
                }
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                header
                count(size: 34)
                Spacer(minLength: 0)
                pills
            }
            .frame(width: 118)
            VStack(spacing: 7) {
                ForEach(projects.prefix(3)) { row($0) }
                Spacer(minLength: 0)
            }
        }
    }

    private func count(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: "\(toDo)").font(.widgetFigure(size))
            Text(loc("of \(projects.count) to do"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// One pill per project, up to the width of the widget.
    private var pills: some View {
        HStack(spacing: 3) {
            ForEach(projects.prefix(8)) { project in
                Capsule().fill(tint(project)).frame(height: 5).widgetAccentable(project.needsWork)
            }
        }
    }

    private func row(_ project: GitRepository) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol(project))
                .font(.system(size: 14))
                .foregroundStyle(tint(project))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(DeveloperText.middleTruncated(project.status?.head ?? "—", to: 22))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            counts(project)
        }
    }

    @ViewBuilder
    private func counts(_ project: GitRepository) -> some View {
        if let status = project.status {
            if project.needsWork {
                HStack(spacing: 6) {
                    if status.changed + status.conflicted > 0 {
                        count("pencil", status.changed + status.conflicted, Palette.orange)
                    }
                    if status.ahead > 0 {
                        count("arrow.up", status.ahead, Palette.blue)
                    }
                    if status.behind > 0 {
                        count("arrow.down", status.behind, Palette.blue)
                    }
                }
            } else {
                Text(loc("Up to date")).font(.system(size: 11)).foregroundStyle(Palette.green).lineLimit(1)
            }
        } else {
            Text(loc("No access")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func count(_ symbol: String, _ value: Int, _ tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(tint)
            Text(verbatim: "\(value)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }

    private func details(_ project: GitRepository) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(project.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            if let status = project.status {
                Text(status.head)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.blue)
                    .lineLimit(1)
                Divider()
                WidgetFact(title: loc("Changes"), value: "\(status.changed + status.conflicted)")
                WidgetFact(title: loc("To push"), value: "\(status.ahead)")
                WidgetFact(title: loc("To pull"), value: "\(status.behind)")
                if let upstream = status.upstream {
                    WidgetFact(title: loc("Upstream"), value: upstream)
                }
            }
            if let date = project.lastCommit {
                WidgetFact(title: loc("Last commit"), value: DeveloperText.relative(date, to: context.now))
            }
            Spacer(minLength: 0)
            Text(loc("Read-only: never commits, fetches or pushes."))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
    }

    private func symbol(_ project: GitRepository) -> String {
        guard let status = project.status else { return "questionmark.circle" }
        if !status.isClean {
            return "pencil.circle"
        }
        if status.behind > 0 {
            return "arrow.down.circle"
        }
        return status.ahead > 0 ? "arrow.up.circle" : "checkmark.circle"
    }

    private func tint(_ project: GitRepository) -> Color {
        guard let status = project.status else { return Palette.gray }
        if !status.isClean {
            return Palette.orange
        }
        return status.ahead + status.behind > 0 ? Palette.blue : Palette.green.opacity(0.7)
    }
}
