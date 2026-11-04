import GlassWorkCore
import SwiftUI
import WidgetKit

/// Pull requests waiting for you and the state of your own.
struct GitHubWidget: View {
    let context: TimeContext

    private let symbol = "arrow.triangle.pull"

    private var data: WidgetGitHub? {
        context.snapshot.github
    }

    private var requested: [PullRequestSummary] {
        data?.requested ?? []
    }

    private var mine: [PullRequestSummary] {
        data?.mine ?? []
    }

    var body: some View {
        if let data {
            switch data.access {
            case .ready:
                content
            case .notInstalled:
                WidgetEmptyState(
                    symbol: symbol,
                    title: loc("The gh tool is not installed"),
                    detail: context.size == .small ? nil : "brew install gh",
                    tint: Palette.purple
                )
            case .notSignedIn:
                WidgetEmptyState(
                    symbol: symbol,
                    title: loc("Not signed in to gh"),
                    detail: context.size == .small ? nil : "gh auth login",
                    tint: Palette.purple
                )
            }
        } else {
            WidgetChecking(symbol: symbol, tint: Palette.purple)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch context.size {
        case .small:
            summary(figure: 44)
        case .medium:
            HStack(spacing: 14) {
                summary(figure: 44).frame(width: 130)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(requested.prefix(2)) { requestRow($0, showsSize: false) }
                    ForEach(mine.prefix(requested.isEmpty ? 3 : 1)) { mineRow($0, showsStatus: false) }
                    Spacer(minLength: 0)
                }
            }
        case .large:
            VStack(alignment: .leading, spacing: 8) {
                title
                WidgetSection(title: "\(loc("Review requested")) · \(requested.count)")
                ForEach(requested.prefix(3)) { requestRow($0, showsSize: true) }
                Divider()
                WidgetSection(title: "\(loc("Your pull requests")) · \(mine.count)")
                ForEach(mine.prefix(3)) { mineRow($0, showsStatus: true) }
                Spacer(minLength: 0)
                footnote(loc("Click a pull request to open it on GitHub"))
            }
        case .extraLarge:
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    WidgetHeader(title: loc("GitHub"), symbol: symbol, tint: Palette.purple)
                    count(figure: 36)
                    WidgetSection(title: loc("Review requested"))
                    ForEach(requested.prefix(4)) { requestRow($0, showsSize: true) }
                    Spacer(minLength: 0)
                    footnote(loc("Requested of you or your teams"))
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        WidgetSection(title: loc("Your pull requests"))
                        Spacer(minLength: 6)
                        footnote(updated)
                    }
                    ForEach(mine.prefix(4)) { detailedRow($0) }
                    Spacer(minLength: 0)
                }
                .frame(width: 368)
            }
        }
    }

    private var title: some View {
        HStack {
            WidgetHeader(title: loc("GitHub"), symbol: symbol, tint: Palette.purple)
            Spacer(minLength: 6)
            footnote(updated)
        }
    }

    private var updated: String {
        guard let date = data?.updatedAt else { return "" }
        return loc("Updated \(age(date))")
    }

    private func age(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: context.now)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
    }

    private func summary(figure: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(title: loc("GitHub"), symbol: symbol, tint: Palette.purple)
            count(figure: figure)
            Spacer(minLength: 0)
            if !mine.isEmpty {
                Text(loc("Your checks")).font(.system(size: 10)).foregroundStyle(.tertiary)
                HStack(spacing: 5) {
                    ForEach(mine.prefix(5)) { checkMark($0.checks) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func count(figure: CGFloat) -> some View {
        if requested.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: figure * 0.8))
                    .foregroundStyle(Palette.green)
                    .widgetAccentable()
                Text(loc("Nothing to review")).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        } else if context.size == .extraLarge {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: "\(requested.count)").font(.widgetFigure(figure))
                Text(loc("to review")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(requested.count)").font(.widgetFigure(figure))
                Text(loc("to review")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    private func checkMark(_ checks: PullRequestSummary.Checks) -> some View {
        let (name, tint): (String, Color) = switch checks {
        case .passing: ("checkmark.circle.fill", Palette.green)
        case .failing: ("xmark.circle.fill", Palette.red)
        case .running: ("ellipsis.circle.fill", Palette.orange)
        case .none: ("circle", Palette.gray)
        }
        return Image(systemName: name).font(.system(size: 14)).foregroundStyle(tint).widgetAccentable()
    }

    private func place(_ pull: PullRequestSummary) -> String {
        let name = pull.repository.split(separator: "/").last.map(String.init) ?? pull.repository
        return "\(age(pull.updatedAt)) · \(name)#\(pull.number)"
    }

    @ViewBuilder
    private func link(_ pull: PullRequestSummary, @ViewBuilder content: () -> some View) -> some View {
        if let url = URL(string: pull.url) {
            Link(destination: url, label: content).buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func requestRow(_ pull: PullRequestSummary, showsSize: Bool) -> some View {
        link(pull) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.purple).widgetAccentable()
                rowText(pull)
                if showsSize {
                    Spacer(minLength: 4)
                    Text(verbatim: "+\(pull.additions)").foregroundStyle(Palette.green)
                    Text(verbatim: "−\(pull.deletions)").foregroundStyle(Palette.red)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
        }
    }

    private func rowText(_ pull: PullRequestSummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(pull.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(place(pull)).font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func mineRow(_ pull: PullRequestSummary, showsStatus: Bool) -> some View {
        link(pull) {
            HStack(spacing: 8) {
                checkMark(pull.checks)
                rowText(pull)
                if showsStatus {
                    Spacer(minLength: 4)
                    status(pull)
                }
            }
        }
    }

    private func detailedRow(_ pull: PullRequestSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            mineRow(pull, showsStatus: true)
            let total = pull.checksTotal
            ThinBar(value: total == 0 ? 0 : Double(pull.checksPassed) / Double(total), tint: tint(pull.checks))
            Text(loc("Checks \(pull.checksPassed) of \(total)"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func tint(_ checks: PullRequestSummary.Checks) -> Color {
        switch checks {
        case .passing: Palette.green
        case .failing: Palette.red
        case .running: Palette.orange
        case .none: Palette.gray
        }
    }

    /// Checks speak first: a review means little on a red build.
    private func status(_ pull: PullRequestSummary) -> some View {
        let (text, color): (String, Color) = switch (pull.checks, pull.review) {
        case (.failing, _): (loc("\(pull.checksFailed) failing"), Palette.red)
        case (.running, _): (loc("Running"), Palette.orange)
        case (_, .changesRequested): (loc("Changes requested"), Palette.orange)
        case (_, .approved): (loc("Approved"), Palette.green)
        case (.passing, .none): (loc("Checks passed"), Palette.green)
        case (.none, .none): ("", .clear)
        }
        return Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(color).lineLimit(1)
    }
}
