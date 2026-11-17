import Foundation

public enum TopAppsRanking: String, Codable, Sendable, CaseIterable {
    case cpu, memory
}

/// How the Top Apps widget ranks and how many apps it lists. The widget cannot read Settings, so the app
/// copies this into the snapshot.
public struct TopAppsOptions: Codable, Sendable, Equatable {
    public static let counts = [3, 5, 8]
    /// The small and medium sizes have room for this many rows, whatever was asked for.
    public static let compactLimit = 4

    public var ranking = TopAppsRanking.cpu
    /// One of `counts`. Nil lists what fits the size, as the widget did before there was a choice.
    public var count: Int?

    public init(ranking: TopAppsRanking = .cpu, count: Int? = nil) {
        self.ranking = ranking
        self.count = count
    }

    public init(options: [String: String]) {
        ranking = options[ItemOption.topAppsRanking].flatMap(TopAppsRanking.init) ?? .cpu
        count = options[ItemOption.topAppsCount].flatMap(Int.init).flatMap { Self.counts.contains($0) ? $0 : nil }
    }

    /// Rows for a widget size. Small and medium keep to what fits.
    public func limit(for size: WidgetSize) -> Int {
        let compact = size == .small || size == .medium
        guard let count else { return compact ? Self.compactLimit : 10 }
        return compact ? min(count, Self.compactLimit) : count
    }

    /// The processes in the order the widget lists them. CPU needs two reads, so memory ranks from apps even
    /// before the CPU of any app is known.
    public func ranked(_ snapshot: WidgetSnapshot, limit: Int) -> [ProcessUsage] {
        let ordered = switch ranking {
        case .cpu: snapshot.topUsage.sorted { $0.cpu > $1.cpu }
        case .memory: (snapshot.apps ?? snapshot.processes).sorted { $0.memory > $1.memory }
        }
        return Array(ordered.prefix(limit))
    }
}
