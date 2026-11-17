import AppKit
import Foundation
@testable import GlassWorkCore
@testable import GlassWorkUI
import SnapshotTesting
import SwiftUI
import Testing

/// Reviews, Actions and Contributions with data and when `gh` is missing. Pixel snapshots run locally only.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GW_SKIP_SNAPSHOTS"] == nil))
struct GitHubDetailSnapshotTests {
    nonisolated static let kinds: [WidgetKind] = [.githubReviews, .githubActions, .contributions]

    private var withData: WidgetSnapshot {
        var snapshot = WidgetSnapshot(date: sampleNow)
        snapshot.githubAccess = .ready
        let titles = ["Glass cards", "Fix widget refresh", "Dock badges", "Sparkle setup", "Docs pass", "Tidy tests"]
        let hours: [Double] = [3, 20, 40, 70, 110, 200]
        snapshot.reviews = zip(titles, hours).enumerated().map { index, pair in
            PullRequest(
                title: pair.0,
                repository: "me/glasswork",
                number: 140 + index,
                url: "https://github.com/me/glasswork/pull/\(140 + index)",
                updatedAt: sampleNow,
                createdAt: sampleNow.addingTimeInterval(-pair.1 * 3600)
            )
        }
        let states: [WorkflowState] = [.running, .passed, .failed, .passed, .passed, .other, .passed, .failed]
        snapshot.runs = states.enumerated().map { index, state in
            let created = sampleNow.addingTimeInterval(-Double(index) * 5400 - 300)
            return WorkflowRun(
                id: index,
                name: ["Build", "Tests", "Deploy", "Lint"][index % 4],
                branch: index % 2 == 0 ? "main" : "fix/ui",
                state: state,
                createdAt: created,
                repository: "me/glasswork",
                startedAt: created,
                updatedAt: created.addingTimeInterval(Double(120 + index * 45))
            )
        }
        snapshot.contributions = (0 ..< 364).map { index in
            ContributionDay(
                date: "2026-\(index / 31 + 1)-\(index % 31 + 1)",
                contributions: index % 7 == 0 ? 0 : index % 9
            )
        }
        snapshot.contributionSummary = ContributionSummary(
            commits: 412,
            pullRequests: 38,
            issues: 9,
            repositories: [
                .init(name: "me/glasswork", commits: 260),
                .init(name: "me/pocket-api", commits: 96),
                .init(name: "me/notes", commits: 31),
            ]
        )
        return snapshot
    }

    private func render(_ kind: WidgetKind, _ snapshot: WidgetSnapshot, _ name: String, sizes: [WidgetSize]) {
        for size in sizes {
            for dark in [true, false] {
                widgetSnapshot(
                    WidgetFace(kind: kind, size: size, snapshot: snapshot, now: sampleNow),
                    size: size,
                    dark: dark,
                    named: "\(kind.rawValue)-\(size.rawValue)-\(name)-\(dark ? "dark" : "light")"
                )
            }
        }
    }

    @Test(arguments: kinds)
    func rendersEverySizeWithData(kind: WidgetKind) {
        render(kind, withData, "data", sizes: WidgetSize.allCases)
    }

    @Test(arguments: kinds)
    func saysWhenGhIsMissing(kind: WidgetKind) {
        var snapshot = withData
        snapshot.githubAccess = .notInstalled
        render(kind, snapshot, "no-tool", sizes: [.small, .large])
    }

    @Test(arguments: kinds)
    func saysWhenGhIsNotSignedIn(kind: WidgetKind) {
        var snapshot = withData
        snapshot.githubAccess = .notSignedIn
        render(kind, snapshot, "signed-out", sizes: [.medium])
    }
}
