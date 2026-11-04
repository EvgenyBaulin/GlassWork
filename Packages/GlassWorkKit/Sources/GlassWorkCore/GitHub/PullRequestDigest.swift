import Foundation

/// One pull request with what a glance needs: size, checks and the reviewers' verdict.
public struct PullRequestSummary: Codable, Sendable, Equatable, Identifiable {
    public enum Review: String, Codable, Sendable {
        case none, approved, changesRequested
    }

    public enum Checks: Sendable, Equatable {
        case none, passing, running, failing
    }

    public var id: String {
        url
    }

    public var title: String
    public var repository: String
    public var number: Int
    public var url: String
    public var updatedAt: Date
    public var additions: Int
    public var deletions: Int
    public var review: Review
    public var checksPassed: Int
    public var checksFailed: Int
    public var checksRunning: Int

    public init(
        title: String,
        repository: String,
        number: Int,
        url: String,
        updatedAt: Date,
        additions: Int = 0,
        deletions: Int = 0,
        review: Review = .none,
        checksPassed: Int = 0,
        checksFailed: Int = 0,
        checksRunning: Int = 0
    ) {
        self.title = title
        self.repository = repository
        self.number = number
        self.url = url
        self.updatedAt = updatedAt
        self.additions = additions
        self.deletions = deletions
        self.review = review
        self.checksPassed = checksPassed
        self.checksFailed = checksFailed
        self.checksRunning = checksRunning
    }

    public var checksTotal: Int {
        checksPassed + checksFailed + checksRunning
    }

    /// A failure outweighs a run still going: it cannot turn green any more.
    public var checks: Checks {
        if checksFailed > 0 {
            return .failing
        }
        if checksRunning > 0 {
            return .running
        }
        return checksPassed > 0 ? .passing : .none
    }
}

/// What the `gh` tool could tell about the user's pull requests.
public struct WidgetGitHub: Codable, Sendable, Equatable {
    public enum Access: String, Codable, Sendable {
        case ready, notInstalled, notSignedIn
    }

    public var access: Access
    /// Waiting for the user's review, newest first.
    public var requested: [PullRequestSummary]
    /// The user's own open pull requests, newest first.
    public var mine: [PullRequestSummary]
    public var updatedAt: Date?

    public init(
        access: Access = .ready,
        requested: [PullRequestSummary] = [],
        mine: [PullRequestSummary] = [],
        updatedAt: Date? = nil
    ) {
        self.access = access
        self.requested = requested
        self.mine = mine
        self.updatedAt = updatedAt
    }
}

private struct DigestContext: Decodable {
    let status: String?
    let conclusion: String?
    let state: String?
}

private struct DigestContexts: Decodable {
    let nodes: [DigestContext]
}

private struct DigestRollup: Decodable {
    let contexts: DigestContexts
}

private struct DigestCommit: Decodable {
    let statusCheckRollup: DigestRollup?
}

private struct DigestCommitNode: Decodable {
    let commit: DigestCommit
}

private struct DigestCommits: Decodable {
    let nodes: [DigestCommitNode]
}

private struct DigestRepository: Decodable {
    let nameWithOwner: String
}

private struct DigestRow: Decodable {
    let title: String?
    let number: Int?
    let url: String?
    let updatedAt: Date?
    let additions: Int?
    let deletions: Int?
    let reviewDecision: String?
    let repository: DigestRepository?
    let commits: DigestCommits?
}

private struct DigestList: Decodable {
    let nodes: [DigestRow]
}

private struct DigestViewer: Decodable {
    let pullRequests: DigestList
}

private struct DigestPayload: Decodable {
    let requested: DigestList
    let viewer: DigestViewer
}

private struct DigestRoot: Decodable {
    let data: DigestPayload
}

public extension GitHubParser {
    /// Both lists in one call. `gh search prs` cannot report diff sizes or checks.
    static let digestQuery: String = {
        let fields = """
        title number url updatedAt additions deletions reviewDecision repository{nameWithOwner} \
        commits(last:1){nodes{commit{statusCheckRollup{contexts(first:50){nodes{__typename \
        ...on CheckRun{status conclusion} ...on StatusContext{state}}}}}}}
        """
        return """
        query{requested:search(query:"is:open is:pr archived:false review-requested:@me",type:ISSUE,first:20)\
        {nodes{...on PullRequest{\(fields)}}} \
        viewer{pullRequests(states:OPEN,first:20,orderBy:{field:UPDATED_AT,direction:DESC})\
        {nodes{\(fields)}}}}
        """
    }()

    /// The answer to `digestQuery`. Nil for anything else, so a failed call keeps the last good lists.
    static func digest(_ json: Data) -> (requested: [PullRequestSummary], mine: [PullRequestSummary])? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let root = try? decoder.decode(DigestRoot.self, from: json) else { return nil }
        return (
            root.data.requested.nodes.compactMap(summary),
            root.data.viewer.pullRequests.nodes.compactMap(summary)
        )
    }

    private static func summary(_ row: DigestRow) -> PullRequestSummary? {
        // The search can also match rows the fragment does not cover, which arrive empty.
        guard let title = row.title, let number = row.number, let url = row.url,
              let updatedAt = row.updatedAt, let repository = row.repository else { return nil }
        var item = PullRequestSummary(
            title: title,
            repository: repository.nameWithOwner,
            number: number,
            url: url,
            updatedAt: updatedAt,
            additions: row.additions ?? 0,
            deletions: row.deletions ?? 0,
            review: review(row.reviewDecision)
        )
        for context in row.commits?.nodes.last?.commit.statusCheckRollup?.contexts.nodes ?? [] {
            switch check(status: context.status, conclusion: context.conclusion, state: context.state) {
            case .passing: item.checksPassed += 1
            case .failing: item.checksFailed += 1
            case .running: item.checksRunning += 1
            case .none: break
            }
        }
        return item
    }

    private static func review(_ decision: String?) -> PullRequestSummary.Review {
        switch decision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        default: .none
        }
    }

    /// A check run has a status and a conclusion; an old-style status has only a state.
    private static func check(status: String?, conclusion: String?, state: String?) -> PullRequestSummary.Checks {
        if let state {
            switch state {
            case "SUCCESS": return .passing
            case "FAILURE", "ERROR": return .failing
            default: return .running
            }
        }
        guard status == "COMPLETED" else { return .running }
        switch conclusion {
        case "SUCCESS": return .passing
        case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED": return .failing
        default: return .none
        }
    }
}
