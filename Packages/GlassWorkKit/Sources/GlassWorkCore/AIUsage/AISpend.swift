import Foundation

/// Local consumption, not a subscription balance or a limit.
public struct AISpendTotals: Codable, Sendable, Equatable {
    public var aiCredits: Double
    public var premiumRequests: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedTokens: Int

    public init(
        aiCredits: Double = 0,
        premiumRequests: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0
    ) {
        self.aiCredits = aiCredits
        self.premiumRequests = premiumRequests
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
    }

    mutating func add(_ other: Self) {
        aiCredits += other.aiCredits
        premiumRequests += other.premiumRequests
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cachedTokens += other.cachedTokens
    }
}

public struct AIModelSpend: Codable, Sendable, Equatable, Identifiable {
    public let model: String
    public let displayName: String
    public var totals: AISpendTotals

    public var id: String {
        model
    }

    public init(model: String, displayName: String, totals: AISpendTotals) {
        self.model = model
        self.displayName = displayName
        self.totals = totals
    }
}

public struct AISpend: Codable, Sendable, Equatable {
    public let today: AISpendTotals
    public let last7Days: AISpendTotals
    public let month: AISpendTotals
    /// Models in the current calendar month, highest consumption first.
    public let topModels: [AIModelSpend]

    public init(
        today: AISpendTotals,
        last7Days: AISpendTotals,
        month: AISpendTotals,
        topModels: [AIModelSpend] = []
    ) {
        self.today = today
        self.last7Days = last7Days
        self.month = month
        self.topModels = topModels
    }
}
