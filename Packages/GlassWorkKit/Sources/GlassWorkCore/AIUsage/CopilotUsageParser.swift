import Foundation

public struct CopilotSessionUsage: Sendable, Equatable {
    public let startDate: Date
    public let updatedAt: Date
    public let totals: AISpendTotals
    public let models: [AIModelSpend]
    let entries: [CopilotSpendEntry]
}

struct CopilotSpendEntry: Sendable, Equatable {
    let date: Date
    let totals: AISpendTotals
    let models: [AIModelSpend]
}

/// Decoding the envelope never decodes message or tool payloads.
private struct CopilotEnvelope: Decodable {
    let type: String
    let timestamp: String?
}

private struct CopilotEvent<Payload: Decodable>: Decodable {
    let data: Payload
}

private struct CopilotStart: Decodable {
    let startTime: String?
}

private struct CopilotRecord: Decodable {
    let usage: CopilotCall
}

private struct CopilotCall: Decodable {
    let model: String
    let modelDisplayName: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let cost: Double?
    let copilotUsage: CopilotCredits?

    var totals: AISpendTotals {
        AISpendTotals(
            aiCredits: (copilotUsage?.totalNanoAiu ?? 0) / 1_000_000_000,
            premiumRequests: cost ?? 0,
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cachedTokens: cacheReadTokens ?? 0
        )
    }
}

private struct CopilotCredits: Decodable {
    let totalNanoAiu: Double?
}

private struct CopilotAccounting: Decodable {
    let accountingSnapshot: CopilotSnapshot?
}

private struct CopilotSnapshot: Decodable {
    let totalPremiumRequestCost: Double?
    let totalNanoAiu: Double?
    let sessionStartTime: String?
    let modelMetrics: [String: CopilotModelMetrics]?

    func entry(at date: Date, names: [String: String]) -> CopilotSpendEntry {
        let models = (modelMetrics ?? [:]).map { model, metrics in
            AIModelSpend(model: model, displayName: names[model] ?? model, totals: metrics.totals)
        }.sorted { $0.model < $1.model }
        var totals = AISpendTotals()
        for model in models {
            totals.add(model.totals)
        }
        totals.aiCredits = totalNanoAiu.map { $0 / 1_000_000_000 } ?? totals.aiCredits
        totals.premiumRequests = totalPremiumRequestCost ?? totals.premiumRequests
        return CopilotSpendEntry(date: date, totals: totals, models: models)
    }
}

private struct CopilotModelMetrics: Decodable {
    struct Requests: Decodable {
        let cost: Double?
    }

    struct Tokens: Decodable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadTokens: Int?
    }

    let requests: Requests?
    let usage: Tokens?
    let totalNanoAiu: Double?

    var totals: AISpendTotals {
        AISpendTotals(
            aiCredits: (totalNanoAiu ?? 0) / 1_000_000_000,
            premiumRequests: requests?.cost ?? 0,
            inputTokens: usage?.inputTokens ?? 0,
            outputTokens: usage?.outputTokens ?? 0,
            cachedTokens: usage?.cacheReadTokens ?? 0
        )
    }
}

public enum CopilotUsageParser {
    /// Snapshots replace all preceding calls; calls after the last snapshot are still included.
    /// Cumulative snapshots are attributed to their event date because their per-call billing may differ.
    public static func parse(_ text: String, modifiedAt: Date) -> CopilotSessionUsage? {
        let decoder = JSONDecoder()
        var start: Date?
        var names: [String: String] = [:]
        var entries: [CopilotSpendEntry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let bytes = Data(line.utf8)
            guard let envelope = try? decoder.decode(CopilotEnvelope.self, from: bytes) else { continue }
            let timestamp = envelope.timestamp.flatMap(date)
            switch envelope.type {
            case "session.start":
                let payload = try? decoder.decode(CopilotEvent<CopilotStart>.self, from: bytes).data
                start = payload?.startTime.flatMap(date) ?? timestamp ?? start
            case "session.usage_record":
                guard let call = try? decoder.decode(CopilotEvent<CopilotRecord>.self, from: bytes).data.usage
                else { continue }
                names[call.model] = call.modelDisplayName ?? call.model
                let model = AIModelSpend(
                    model: call.model, displayName: names[call.model] ?? call.model, totals: call.totals
                )
                entries.append(CopilotSpendEntry(
                    date: timestamp ?? start ?? modifiedAt, totals: call.totals, models: [model]
                ))
            case "session.usage_checkpoint", "session.shutdown":
                guard let snapshot = try? decoder.decode(
                    CopilotEvent<CopilotAccounting>.self, from: bytes
                ).data.accountingSnapshot else { continue }
                start = start ?? snapshot.sessionStartTime.flatMap(date)
                entries = [snapshot.entry(at: timestamp ?? start ?? modifiedAt, names: names)]
            default: continue
            }
        }
        guard !entries.isEmpty else { return nil }
        var totals = AISpendTotals()
        for entry in entries {
            totals.add(entry.totals)
        }
        return CopilotSessionUsage(
            startDate: start ?? entries.first?.date ?? modifiedAt,
            updatedAt: entries.map(\.date).max() ?? modifiedAt,
            totals: totals,
            models: mergedModels(entries),
            entries: entries
        )
    }

    static func mergedModels(_ entries: [CopilotSpendEntry]) -> [AIModelSpend] {
        var models: [String: AIModelSpend] = [:]
        for entry in entries {
            for model in entry.models {
                if var previous = models[model.model] {
                    previous.totals.add(model.totals)
                    models[model.model] = previous
                } else {
                    models[model.model] = model
                }
            }
        }
        return models.values.sorted {
            if $0.totals.aiCredits != $1.totals.aiCredits {
                return $0.totals.aiCredits > $1.totals.aiCredits
            }
            if $0.totals.premiumRequests != $1.totals.premiumRequests {
                return $0.totals.premiumRequests > $1.totals.premiumRequests
            }
            if $0.totals.inputTokens != $1.totals.inputTokens {
                return $0.totals.inputTokens > $1.totals.inputTokens
            }
            return $0.model < $1.model
        }
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
