import Foundation
import Observation

/// What one service gave back in one refresh.
struct RateUpdate: Sendable {
    var quotes: [RateQuote]
    var cbrDays: [CBRDay]?
}

/// Talks to the three services. Knows nothing about schedules or the UI.
struct RateService: Sendable {
    let fetcher: any HTTPFetching

    func update(
        _ source: RateSource,
        pairs: [RatePair],
        known: RatesSnapshot,
        now: Date
    ) async throws -> RateUpdate {
        switch source {
        case .cbr: try await cbr(pairs, known: known.cbrDays)
        case .frankfurter: try await frankfurter(pairs, now: now)
        case .coinGecko: try await coinGecko(pairs, known: known)
        }
    }

    private func cbr(_ pairs: [RatePair], known: [CBRDay]) async throws -> RateUpdate {
        guard let url = CBR.latestURL else { throw URLError(.badURL) }
        var days = try await CBR.merged(CBR.day(from: fetcher.data(from: url)), into: known)
        // The charts are a bonus: a missing archive day never fails the refresh.
        while days.count < CBR.historyDays, let link = CBR.archiveURL(days.last?.previousURL),
              let data = try? await fetcher.data(from: link), let older = try? CBR.day(from: data),
              !days.contains(where: { $0.date == older.date })
        {
            days.append(older)
        }
        return RateUpdate(quotes: pairs.compactMap { CBR.quote(for: $0, days: days) }, cbrDays: days)
    }

    private func frankfurter(_ pairs: [RatePair], now: Date) async throws -> RateUpdate {
        var quotes: [RateQuote] = []
        for (base, group) in Dictionary(grouping: pairs, by: \.base) {
            guard let url = Frankfurter.seriesURL(base: base, quotes: group.map(\.quote), now: now) else { continue }
            try await quotes += Frankfurter.quotes(from: fetcher.data(from: url), pairs: group)
        }
        return RateUpdate(quotes: quotes)
    }

    private func coinGecko(_ pairs: [RatePair], known: RatesSnapshot) async throws -> RateUpdate {
        guard let url = CoinGecko.priceURL(pairs: pairs) else { throw URLError(.badURL) }
        var quotes = try await CoinGecko.quotes(from: fetcher.data(from: url), pairs: pairs)
        for index in quotes.indices {
            let pair = quotes[index].pair
            // The chart has a tighter limit than the price, so a refusal keeps the last chart.
            let fresh = await chart(for: pair)
            quotes[index].history = fresh ?? known.quote(for: pair)?.history ?? []
        }
        return RateUpdate(quotes: quotes)
    }

    private func chart(for pair: RatePair) async -> [RatePoint]? {
        guard let url = CoinGecko.chartURL(for: pair), let data = try? await fetcher.data(from: url) else { return nil }
        return try? CoinGecko.history(from: data)
    }
}

/// Exchange rates for the configured pairs. Asks only while something on screen needs them.
@MainActor
@Observable
public final class RatesStore {
    public private(set) var snapshot: RatesSnapshot
    public private(set) var status = FetchStatus.idle
    public private(set) var settings = RatesSettings()
    /// Services that did not answer last time, while others did.
    public private(set) var failedSources: Set<RateSource> = []
    /// Set by the app: true while the module is in the menu bar or a panel is open.
    public var isActive = false

    @ObservationIgnored private let service: RateService
    @ObservationIgnored private let store: SnapshotStore
    @ObservationIgnored private var schedule: RefreshSchedule

    public init(fetcher: any HTTPFetching = URLSessionFetcher(), store: SnapshotStore = SnapshotStore()) {
        service = RateService(fetcher: fetcher)
        self.store = store
        let saved = store.read(RatesSnapshot.self, for: RatesSnapshot.key) ?? RatesSnapshot()
        snapshot = saved
        schedule = RefreshSchedule(lastSuccess: saved.updatedAt)
    }

    /// No service could be reached, so everything on screen is the last known data.
    public var isStale: Bool {
        status == .offline
    }

    public func isUnavailable(_ pair: RatePair) -> Bool {
        !isStale && pair.source.map(failedSources.contains) == true
    }

    public var shownQuote: RateQuote? {
        settings.shownPair.flatMap(snapshot.quote(for:))
    }

    public func apply(_ new: RatesSettings) {
        guard new != settings else { return }
        let pairsChanged = new.pairs != settings.pairs
        settings = new
        if pairsChanged {
            schedule.expire()
        }
    }

    /// Called on every monitor read, which also pauses this during sleep.
    public func tick(at date: Date) {
        guard isActive, status != .loading, !settings.pairs.isEmpty, schedule.isDue(at: date) else { return }
        Task { await refresh(at: date) }
    }

    /// Clears the wait after a failure, for the Retry button.
    public func retry() async {
        schedule.expire()
        await refresh()
    }

    /// Asks every service in parallel. One that fails leaves the others' results in place.
    public func refresh(at date: Date = Date()) async {
        guard status != .loading else { return }
        status = .loading
        let groups = Dictionary(grouping: settings.pairs.filter { $0.source != nil }) { $0.source ?? .cbr }
        let outcomes = await fetch(groups, at: date)
        apply(outcomes, pairs: settings.pairs, at: date)
    }

    private func fetch(
        _ groups: [RateSource: [RatePair]],
        at date: Date
    ) async -> [RateSource: Result<RateUpdate, any Error>] {
        let service = service
        let known = snapshot
        return await withTaskGroup(of: (RateSource, Result<RateUpdate, any Error>).self) { group in
            for (source, pairs) in groups {
                group.addTask {
                    do {
                        return try await (
                            source,
                            .success(service.update(source, pairs: pairs, known: known, now: date))
                        )
                    } catch {
                        return (source, .failure(error))
                    }
                }
            }
            var outcomes: [RateSource: Result<RateUpdate, any Error>] = [:]
            for await (source, outcome) in group {
                outcomes[source] = outcome
            }
            return outcomes
        }
    }

    private func apply(_ outcomes: [RateSource: Result<RateUpdate, any Error>], pairs: [RatePair], at date: Date) {
        var new = snapshot
        var failed: [RateSource: any Error] = [:]
        for (source, outcome) in outcomes {
            switch outcome {
            case let .success(update):
                new.quotes.removeAll { $0.source == source }
                new.quotes += update.quotes
                new.cbrDays = update.cbrDays ?? new.cbrDays
            case let .failure(error):
                failed[source] = error
            }
        }
        new.quotes.removeAll { !pairs.contains($0.pair) }
        let anySucceeded = failed.count < outcomes.count
        if anySucceeded {
            new.updatedAt = date
            snapshot = new
            try? store.write(new, for: RatesSnapshot.key)
        }
        failedSources = Set(failed.keys)
        schedule.record(success: failed.isEmpty, at: date)
        status = Self.status(failed: failed.values.map(\.self), anySucceeded: anySucceeded)
    }

    private static func status(failed: [any Error], anySucceeded: Bool) -> FetchStatus {
        if failed.isEmpty {
            return .ready
        }
        return !anySucceeded && failed.allSatisfy(FetchStatus.isOffline) ? .offline : .failed
    }
}
