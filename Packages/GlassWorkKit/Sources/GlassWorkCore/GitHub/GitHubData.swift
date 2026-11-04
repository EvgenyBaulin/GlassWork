import Foundation

// swiftlint:disable nesting

public struct PullRequest: Codable, Sendable, Equatable, Identifiable {
    public var id: String {
        url
    }

    public var title: String
    public var repository: String
    public var number: Int
    public var url: String
    public var updatedAt: Date
}

public enum WorkflowState: String, Codable, Sendable {
    case running, passed, failed, other
}

public struct WorkflowRun: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    public var branch: String
    public var state: WorkflowState
    public var createdAt: Date
    /// `owner/name`. Optional so runs saved before it existed still decode.
    public var repository: String?

    /// The name without the owner, which is what a small widget has room for.
    public var repositoryName: String? {
        repository?.split(separator: "/").last.map(String.init)
    }
}

public struct ContributionDay: Codable, Sendable, Equatable {
    public var date: String
    public var contributions: Int
}

/// Parsers for `gh` output. All GitHub data comes through the user's own `gh` login.
public enum GitHubParser {
    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// `gh search prs --review-requested=@me --state=open --json title,repository,number,url,updatedAt`.
    public static func pullRequests(_ json: Data) -> [PullRequest] {
        struct Row: Decodable {
            struct Repository: Decodable { let nameWithOwner: String }
            let title: String
            let repository: Repository
            let number: Int
            let url: String
            let updatedAt: Date
        }
        let rows = (try? decoder.decode([Row].self, from: json)) ?? []
        return rows.map {
            PullRequest(
                title: $0.title,
                repository: $0.repository.nameWithOwner,
                number: $0.number,
                url: $0.url,
                updatedAt: $0.updatedAt
            )
        }
    }

    /// `gh api user/repos --jq .[].full_name`: one `owner/name` per line.
    public static func repositories(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("/") }
    }

    /// `gh run list --json databaseId,displayTitle,headBranch,status,conclusion,createdAt`.
    public static func workflowRuns(_ json: Data, repository: String? = nil) -> [WorkflowRun] {
        struct Row: Decodable {
            let databaseId: Int
            let displayTitle: String
            let headBranch: String
            let status: String
            let conclusion: String?
            let createdAt: Date
        }
        let rows = (try? decoder.decode([Row].self, from: json)) ?? []
        return rows.map {
            WorkflowRun(
                id: $0.databaseId,
                name: $0.displayTitle,
                branch: $0.headBranch,
                state: state(status: $0.status, conclusion: $0.conclusion),
                createdAt: $0.createdAt,
                repository: repository
            )
        }
    }

    static func state(status: String, conclusion: String?) -> WorkflowState {
        guard status == "completed" else { return .running }
        switch conclusion {
        case "success": return .passed
        case "failure", "timed_out": return .failed
        default: return .other
        }
    }

    /// The contribution calendar from `gh api graphql`.
    public static func contributions(_ json: Data) -> [ContributionDay] {
        struct Root: Decodable {
            struct Week: Decodable {
                struct Day: Decodable {
                    let date: String
                    let contributionCount: Int
                }

                let contributionDays: [Day]
            }

            struct Calendar: Decodable { let weeks: [Week] }
            struct Collection: Decodable { let contributionCalendar: Calendar }
            struct Viewer: Decodable { let contributionsCollection: Collection }
            struct Payload: Decodable { let viewer: Viewer }
            let data: Payload
        }
        guard let root = try? JSONDecoder().decode(Root.self, from: json) else { return [] }
        return root.data.viewer.contributionsCollection.contributionCalendar.weeks
            .flatMap(\.contributionDays)
            .map { ContributionDay(date: $0.date, contributions: $0.contributionCount) }
    }

    /// Longest run of days ending today with at least one contribution.
    public static func currentStreak(_ days: [ContributionDay]) -> Int {
        days.reversed().prefix { $0.contributions > 0 }.count
    }
}

// swiftlint:enable nesting
