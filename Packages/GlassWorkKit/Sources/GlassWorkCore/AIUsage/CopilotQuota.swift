import Foundation

private struct CopilotQuotaAnswer: Decodable {
    let quotaSnapshots: [String: CopilotQuotaSnapshot]?
    let quotaResetDateUTC: String?

    enum CodingKeys: String, CodingKey {
        case quotaSnapshots = "quota_snapshots", quotaResetDateUTC = "quota_reset_date_utc"
    }
}

private struct CopilotQuotaSnapshot: Decodable {
    let entitlement: Double?
    let percentRemaining: Double?
    let unlimited: Bool?
    let hasQuota: Bool?

    enum CodingKeys: String, CodingKey {
        case entitlement, unlimited
        case percentRemaining = "percent_remaining", hasQuota = "has_quota"
    }

    /// A limit that counts: not unlimited and not empty.
    var usedShare: Double? {
        guard unlimited != true, hasQuota != false, let entitlement, entitlement > 0,
              let percentRemaining
        else { return nil }
        return min(max(1 - percentRemaining / 100, 0), 1)
    }
}

/// The Copilot plan's monthly limit, from `gh api /copilot_internal/user`: the address Copilot's editor
/// extensions read the same numbers from. `gh` signs the request with its own login, so GlassWork never sees a
/// token, and asking costs no credits. Only the quota fields are decoded; the login and ids in the answer are
/// left alone.
public enum CopilotQuota {
    public static let arguments = ["api", "/copilot_internal/user"]
    public static let timeout: TimeInterval = 20

    /// Premium requests on paid plans, chat credits on the free one: whichever the plan limits.
    private static let preferred = ["premium_interactions", "chat"]

    public static func window(from text: String) -> AIWindow? {
        guard let answer = try? JSONDecoder().decode(CopilotQuotaAnswer.self, from: Data(text.utf8)),
              let snapshots = answer.quotaSnapshots,
              let used = preferred.lazy.compactMap({ snapshots[$0]?.usedShare }).first
        else { return nil }
        let reset = answer.quotaResetDateUTC.flatMap { try? Date($0, strategy: .iso8601) }
            ?? answer.quotaResetDateUTC.flatMap {
                try? Date($0, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))
            }
        return AIWindow(kind: .month, used: used, resetsAt: reset)
    }
}
